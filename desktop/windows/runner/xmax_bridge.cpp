#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <flutter_windows.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <exception>
#include <memory>
#include <optional>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <vector>

#include <xmax/xmax.hpp>

using Microsoft::WRL::ComPtr;

namespace {

struct Apartment {
  HRESULT status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ~Apartment() {
    if (SUCCEEDED(status)) CoUninitialize();
  }
};

std::mutex registrar_mutex;
FlutterDesktopTextureRegistrarRef registrar = nullptr;

struct Pixels {
  size_t width;
  size_t height;
  std::vector<uint8_t> rgba;
};

struct TextureSlot {
  std::mutex mutex;
  std::shared_ptr<const Pixels> latest;
  int64_t id = -1;
};

struct TextureLease {
  std::shared_ptr<const Pixels> pixels;
  FlutterDesktopPixelBuffer buffer{};
};

const FlutterDesktopPixelBuffer* CopyPixels(size_t, size_t, void* data) {
  auto* slot = static_cast<TextureSlot*>(data);
  std::lock_guard<std::mutex> lock(slot->mutex);
  if (!slot->latest) return nullptr;
  auto* lease = new TextureLease{slot->latest};
  lease->buffer.buffer = lease->pixels->rgba.data();
  lease->buffer.width = lease->pixels->width;
  lease->buffer.height = lease->pixels->height;
  lease->buffer.release_context = lease;
  lease->buffer.release_callback = [](void* value) {
    delete static_cast<TextureLease*>(value);
  };
  return &lease->buffer;
}

void ReleaseTexture(TextureSlot* slot) {
  if (!slot) return;
  std::lock_guard<std::mutex> lock(registrar_mutex);
  if (registrar && slot->id >= 0) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        registrar, slot->id,
        [](void* data) { delete static_cast<TextureSlot*>(data); }, slot);
  } else {
    delete slot;
  }
}

using Texture = std::unique_ptr<TextureSlot, decltype(&ReleaseTexture)>;

Texture NewTexture() {
  Texture slot(new TextureSlot(), ReleaseTexture);
  {
    std::lock_guard<std::mutex> lock(registrar_mutex);
    if (registrar) {
      FlutterDesktopTextureInfo info{};
      info.type = kFlutterDesktopPixelBufferTexture;
      info.pixel_buffer_config.callback = CopyPixels;
      info.pixel_buffer_config.user_data = slot.get();
      slot->id = FlutterDesktopTextureRegistrarRegisterExternalTexture(
          registrar, &info);
    }
  }
  if (slot->id < 0) throw std::runtime_error("Could not register video texture.");
  return slot;
}

struct Session {
  Session(const char* token, const char* camera)
      : client(xmax::XmaxConfiguration{token, xmax::XmaxEnvironment::global}),
        realtime(client.create_realtime(xmax::RealtimeConfiguration{})),
        local(realtime.create_local_camera_stream(CameraOptions(camera))) {}

  static xmax_local_camera_options CameraOptions(const char* camera) {
    xmax_local_camera_options options{};
    options.video_format = {1920, 1080, 30};
    options.device_id = *camera == '\0' ? nullptr : camera;
    return options;
  }

  ~Session() {
    running.store(false);
    if (frame_thread.joinable()) frame_thread.join();
    if (generation_thread.joinable()) generation_thread.join();
    try {
      realtime.close();
    } catch (const std::exception&) {
      // The controller still releases its resources on destruction.
    }
  }

  xmax::client client;
  xmax::realtime realtime;
  xmax::realtime_media_stream local;
  std::mutex generation_mutex;
  std::optional<xmax::realtime_media_stream> remote;
  int64_t timestamps[2] = {-1, -1};
  Texture local_texture = NewTexture();
  Texture remote_texture = NewTexture();
  std::mutex obs_mutex;
  std::shared_ptr<const Pixels> obs_frame;
  int64_t obs_timestamp = -1;
  int64_t encoded_timestamp = -1;
  std::vector<uint8_t> jpeg;
  std::atomic<bool> running{true};
  std::atomic<int> frame_updates{0};
  std::atomic<bool> generation_failed{false};
  std::thread frame_thread;
  std::thread generation_thread;
};

void Check(HRESULT result) {
  if (FAILED(result)) throw std::runtime_error("Windows JPEG encoding failed.");
}

std::shared_ptr<Pixels> ConvertFrame(const xmax::frame& frame) {
  const auto view = frame.view();
  const auto width = view.width;
  const auto height = view.height;
  if (width == 0 || height == 0 || width > 4096 || height > 4096) {
    return {};
  }
  const bool mirror = frame.mirrored();
  auto pixels = std::make_shared<Pixels>();
  pixels->width = width;
  pixels->height = height;
  pixels->rgba.resize(static_cast<size_t>(width) * height * 4);
  const auto channel = [](int value) {
    return static_cast<uint8_t>(std::clamp(value, 0, 255));
  };
  for (uint32_t y = 0; y < height; ++y) {
    for (uint32_t x = 0; x < width; ++x) {
      const auto source_x = mirror ? width - x - 1 : x;
      auto* output = pixels->rgba.data() + (static_cast<size_t>(y) * width + x) * 4;
      if (view.pixel_format == XMAX_BGRA) {
        const auto* source =
            view.planes[0] + y * view.strides[0] + source_x * 4;
        output[0] = source[2];
        output[1] = source[1];
        output[2] = source[0];
      } else {
        const int luma = view.planes[0][y * view.strides[0] + source_x] - 16;
        const auto chroma_x = source_x / 2;
        const auto chroma_y = y / 2;
        const auto chroma = view.planes[1] + chroma_y * view.strides[1];
        const bool nv12 = view.pixel_format == XMAX_NV12;
        const int u = chroma[nv12 ? chroma_x * 2 : chroma_x] - 128;
        const int v = (nv12 ? chroma[chroma_x * 2 + 1]
                            : view.planes[2][chroma_y * view.strides[2] +
                                             chroma_x]) - 128;
        output[2] = channel((298 * luma + 516 * u + 128) >> 8);
        output[1] = channel((298 * luma - 100 * u - 208 * v + 128) >> 8);
        output[0] = channel((298 * luma + 409 * v + 128) >> 8);
      }
      output[3] = 255;
    }
  }
  return pixels;
}

std::vector<uint8_t> EncodeJpeg(const Pixels& frame) {
  // OBS gets an up-to-720p feed. Keep the in-app texture at its original size.
  const double scale = std::min(
      {1.0, 1280.0 / frame.width, 720.0 / frame.height});
  const auto width = std::max(1u, static_cast<UINT>(frame.width * scale));
  const auto height = std::max(1u, static_cast<UINT>(frame.height * scale));
  std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 3);
  for (UINT y = 0; y < height; ++y) {
    const auto source_row = (y * frame.height / height) * frame.width;
    for (UINT x = 0; x < width; ++x) {
      const auto source = (source_row + x * frame.width / width) * 4;
      const auto target = (static_cast<size_t>(y) * width + x) * 3;
      pixels[target] = frame.rgba[source + 2];
      pixels[target + 1] = frame.rgba[source + 1];
      pixels[target + 2] = frame.rgba[source];
    }
  }
  ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(factory.GetAddressOf())));
  ComPtr<IStream> stream;
  Check(CreateStreamOnHGlobal(nullptr, TRUE, stream.GetAddressOf()));
  ComPtr<IWICBitmapEncoder> encoder;
  Check(factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr,
                               encoder.GetAddressOf()));
  Check(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache));
  ComPtr<IWICBitmapFrameEncode> image;
  Check(encoder->CreateNewFrame(image.GetAddressOf(), nullptr));
  Check(image->Initialize(nullptr));
  Check(image->SetSize(width, height));
  auto format = GUID_WICPixelFormat24bppBGR;
  Check(image->SetPixelFormat(&format));
  if (!IsEqualGUID(format, GUID_WICPixelFormat24bppBGR)) {
    throw std::runtime_error("Windows JPEG encoder rejected the pixel format.");
  }
  Check(image->WritePixels(height, width * 3, static_cast<UINT>(pixels.size()),
                           pixels.data()));
  Check(image->Commit());
  Check(encoder->Commit());
  STATSTG size{};
  Check(stream->Stat(&size, STATFLAG_NONAME));
  if (size.cbSize.HighPart != 0) {
    throw std::runtime_error("Encoded video frame is too large.");
  }
  LARGE_INTEGER start{};
  Check(stream->Seek(start, STREAM_SEEK_SET, nullptr));
  std::vector<uint8_t> result(size.cbSize.LowPart);
  ULONG read = 0;
  Check(stream->Read(result.data(), size.cbSize.LowPart, &read));
  result.resize(read);
  return result;
}

void WriteError(char* error, int capacity, const std::exception& exception) {
  if (capacity > 0) strncpy_s(error, static_cast<size_t>(capacity),
                             exception.what(), _TRUNCATE);
}

}  // namespace

__declspec(dllexport) void SetXmaxTextureRegistrar(
    FlutterDesktopTextureRegistrarRef value) {
  std::lock_guard<std::mutex> lock(registrar_mutex);
  registrar = value;
}

static int UpdateTextures(Session* session);

extern "C" __declspec(dllexport) Session* realface_xmax_start(
    const char* token, const char* prompt, const char* reference,
    const char* camera, char* error,
    int capacity) {
  Apartment apartment;
  try {
    auto session = std::make_unique<Session>(token, camera);
    session->frame_thread = std::thread([state = session.get()] {
      Apartment apartment;
      while (state->running.load()) {
        const auto deadline = std::chrono::steady_clock::now() +
                              std::chrono::milliseconds(16);
        const int updated = UpdateTextures(state);
        if (updated < 0) {
          state->frame_updates.store(-1);
          break;
        }
        state->frame_updates.fetch_or(updated);
        std::this_thread::sleep_until(deadline);
      }
    });
    if (*token != '\0') {
      auto conditions = xmax::realtime_context{prompt, std::nullopt};
      if (*reference != '\0') conditions.reference_path = reference;
      session->generation_thread = std::thread(
          [state = session.get(), conditions = std::move(conditions)] {
            Apartment apartment;
            try {
              auto output =
                  state->realtime.start_generation(state->local, conditions);
              std::lock_guard<std::mutex> lock(state->generation_mutex);
              state->remote = std::move(output);
            } catch (const std::exception&) {
              state->generation_failed.store(true);
            }
          });
    }
    return session.release();
  } catch (const std::exception& exception) {
    WriteError(error, capacity, exception);
    return nullptr;
  }
}

extern "C" __declspec(dllexport) int64_t realface_xmax_texture(
    Session* session, int remote) {
  return (remote ? session->remote_texture : session->local_texture)->id;
}

static int UpdateTextures(Session* session) {
  try {
    int changed = 0;
    for (int remote = 0; remote < 2; ++remote) {
      std::optional<xmax::realtime_media_stream> stream = session->local;
      if (remote) {
        std::lock_guard<std::mutex> lock(session->generation_mutex);
        stream = session->remote;
      }
      if (!stream) continue;
      auto frame = session->realtime.acquire_stream_frame(*stream);
      if (!frame.get()) continue;
      const auto timestamp = frame.view().timestamp_us;
      if (session->timestamps[remote] == timestamp) continue;
      auto pixels = ConvertFrame(frame);
      if (!pixels) continue;
      session->timestamps[remote] = timestamp;
      auto& slot = remote ? session->remote_texture : session->local_texture;
      {
        std::lock_guard<std::mutex> lock(slot->mutex);
        slot->latest = pixels;
      }
      if (remote) {
        std::lock_guard<std::mutex> lock(session->obs_mutex);
        session->obs_frame = pixels;
        session->obs_timestamp = timestamp;
      }
      {
        std::lock_guard<std::mutex> lock(registrar_mutex);
        if (registrar) {
          FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
              registrar, slot->id);
        }
      }
      changed |= 1 << remote;
    }
    return changed;
  } catch (const std::exception&) {
    return -1;
  }
}

// Bit 0 marks a new camera frame; bit 1 marks a new generated frame.
extern "C" __declspec(dllexport) int realface_xmax_poll(Session* session) {
  if (session->generation_failed.load()) return -2;
  return session->frame_updates.exchange(0);
}

extern "C" __declspec(dllexport) const uint8_t* realface_xmax_obs_frame(
    Session* session, int* length) {
  Apartment apartment;
  *length = 0;
  try {
    std::shared_ptr<const Pixels> pixels;
    {
      std::lock_guard<std::mutex> lock(session->obs_mutex);
      if (!session->obs_frame ||
          session->encoded_timestamp == session->obs_timestamp) return nullptr;
      pixels = session->obs_frame;
      session->encoded_timestamp = session->obs_timestamp;
    }
    session->jpeg = EncodeJpeg(*pixels);
    *length = static_cast<int>(session->jpeg.size());
    return session->jpeg.data();
  } catch (const std::exception&) {
    *length = -1;
    return nullptr;
  }
}

extern "C" __declspec(dllexport) void realface_xmax_stop(Session* session) {
  Apartment apartment;
  delete session;
}

extern "C" __declspec(dllexport) int realface_xmax_cameras(
    char* buffer, int capacity) {
  Apartment apartment;
  try {
    xmax::client client(
        xmax::XmaxConfiguration{"", xmax::XmaxEnvironment::global});
    std::string values;
    for (const auto& camera : client.cameras()) {
      values.append(camera.id).push_back('\0');
      values.append(camera.name).push_back('\0');
    }
    if (values.size() > static_cast<size_t>(capacity)) return -1;
    std::memcpy(buffer, values.data(), values.size());
    return static_cast<int>(values.size());
  } catch (const std::exception&) {
    return -1;
  }
}
