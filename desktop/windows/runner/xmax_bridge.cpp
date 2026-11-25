#include <windows.h>

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
    if (output_thread.joinable()) output_thread.join();
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
  std::atomic<bool> show_output{false};
  std::atomic<bool> output_failed{false};
  std::atomic<bool> running{true};
  std::atomic<int> frame_updates{0};
  std::atomic<bool> generation_failed{false};
  std::thread frame_thread;
  std::thread generation_thread;
  std::thread output_thread;
};

struct OutputWindow {
  std::shared_ptr<const Pixels> frame;
};

void PaintOutput(HWND window, const OutputWindow* output) {
  PAINTSTRUCT paint{};
  const auto dc = BeginPaint(window, &paint);
  RECT client{};
  GetClientRect(window, &client);
  const auto width = client.right;
  const auto height = client.bottom;
  const auto* frame = output ? output->frame.get() : nullptr;
  if (!frame || width <= 0 || height <= 0) {
    FillRect(dc, &client, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    EndPaint(window, &paint);
    return;
  }

  const double scale = std::min(static_cast<double>(width) / frame->width,
                                static_cast<double>(height) / frame->height);
  const int draw_width = std::max(1, static_cast<int>(frame->width * scale));
  const int draw_height = std::max(1, static_cast<int>(frame->height * scale));
  const int x = (width - draw_width) / 2;
  const int y = (height - draw_height) / 2;
  const auto black = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  const RECT bars[] = {
      {0, 0, width, y}, {0, y + draw_height, width, height},
      {0, y, x, y + draw_height},
      {x + draw_width, y, width, y + draw_height},
  };
  for (const auto& bar : bars) FillRect(dc, &bar, black);

  struct {
    BITMAPINFOHEADER header;
    DWORD masks[3];
  } dib{};
  dib.header.biSize = sizeof(dib.header);
  dib.header.biWidth = static_cast<LONG>(frame->width);
  dib.header.biHeight = -static_cast<LONG>(frame->height);
  dib.header.biPlanes = 1;
  dib.header.biBitCount = 32;
  dib.header.biCompression = BI_BITFIELDS;
  dib.masks[0] = 0x000000ff;
  dib.masks[1] = 0x0000ff00;
  dib.masks[2] = 0x00ff0000;
  SetStretchBltMode(dc, COLORONCOLOR);
  StretchDIBits(dc, x, y, draw_width, draw_height, 0, 0,
                static_cast<int>(frame->width), static_cast<int>(frame->height),
                frame->rgba.data(), reinterpret_cast<const BITMAPINFO*>(&dib),
                DIB_RGB_COLORS, SRCCOPY);
  EndPaint(window, &paint);
}

LRESULT CALLBACK OutputWindowProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
  switch (message) {
    case WM_NCCREATE: {
      const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
      break;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      PaintOutput(window, reinterpret_cast<const OutputWindow*>(
                              GetWindowLongPtrW(window, GWLP_USERDATA)));
      return 0;
    case WM_SIZE:
      InvalidateRect(window, nullptr, FALSE);
      break;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

HWND CreateOutputWindow(OutputWindow* output) {
  const auto instance = GetModuleHandleW(nullptr);
  constexpr wchar_t window_class[] = L"RealFaceAIOutputWindow";
  WNDCLASSW options{};
  options.lpfnWndProc = OutputWindowProc;
  options.hInstance = instance;
  options.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  options.lpszClassName = window_class;
  if (!RegisterClassW(&options) &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return nullptr;
  }

  return CreateWindowExW(0, window_class, L"RealFaceAI AI Output",
                        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                        960, 580, nullptr, nullptr, instance, output);
}

void RunOutputWindow(Session* session) {
  OutputWindow output;
  HWND window = nullptr;
  while (session->running.load()) {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    if (window && !IsWindow(window)) {
      window = nullptr;
      output.frame.reset();
    }
    if (session->show_output.exchange(false)) {
      if (!window) window = CreateOutputWindow(&output);
      if (window) {
        ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
        SetForegroundWindow(window);
      } else {
        session->output_failed.store(true);
      }
    }
    if (window && !IsIconic(window)) {
      std::shared_ptr<const Pixels> latest;
      {
        const auto& slot = session->remote_texture;
        std::lock_guard<std::mutex> lock(slot->mutex);
        latest = slot->latest;
      }
      if (latest != output.frame) {
        output.frame = std::move(latest);
        InvalidateRect(window, nullptr, FALSE);
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(16));
  }
  if (window) DestroyWindow(window);
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
      session->output_thread = std::thread(RunOutputWindow, session.get());
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
  const int updated = session->frame_updates.exchange(0);
  if (updated < 0) return updated;
  return updated | (session->output_failed.exchange(false) ? 4 : 0);
}

extern "C" __declspec(dllexport) void realface_xmax_open_output(
    Session* session) {
  session->show_output.store(true);
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
