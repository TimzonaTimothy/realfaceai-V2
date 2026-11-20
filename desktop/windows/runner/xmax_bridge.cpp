#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <exception>
#include <memory>
#include <optional>
#include <stdexcept>
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

struct Session {
  Session(const char* token, const char* camera)
      : client(xmax::XmaxConfiguration{token, xmax::XmaxEnvironment::global}),
        realtime(client.create_realtime(xmax::RealtimeConfiguration{})),
        local(realtime.create_local_camera_stream(CameraOptions(camera))) {}

  static xmax_local_camera_options CameraOptions(const char* camera) {
    xmax_local_camera_options options{};
    options.device_id = *camera == '\0' ? nullptr : camera;
    return options;
  }

  xmax::client client;
  xmax::realtime realtime;
  xmax::realtime_media_stream local;
  std::optional<xmax::realtime_media_stream> remote;
  int64_t timestamps[2] = {-1, -1};
  std::vector<uint8_t> jpeg;
};

void Check(HRESULT result) {
  if (FAILED(result)) throw std::runtime_error("Windows JPEG encoding failed.");
}

std::vector<uint8_t> EncodeJpeg(const xmax::frame& frame) {
  const auto view = frame.view();
  const auto width = view.width;
  const auto height = view.height;
  if (width == 0 || height == 0 || width > 4096 || height > 4096) {
    return {};
  }
  const bool mirror = frame.mirrored();
  std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 3);
  const auto channel = [](int value) {
    return static_cast<uint8_t>(std::clamp(value, 0, 255));
  };
  for (uint32_t y = 0; y < height; ++y) {
    for (uint32_t x = 0; x < width; ++x) {
      const auto source_x = mirror ? width - x - 1 : x;
      auto* output = pixels.data() + (static_cast<size_t>(y) * width + x) * 3;
      if (view.pixel_format == XMAX_BGRA) {
        const auto* source =
            view.planes[0] + y * view.strides[0] + source_x * 4;
        std::memcpy(output, source, 3);
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
        output[0] = channel((298 * luma + 516 * u + 128) >> 8);
        output[1] = channel((298 * luma - 100 * u - 208 * v + 128) >> 8);
        output[2] = channel((298 * luma + 409 * v + 128) >> 8);
      }
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

extern "C" __declspec(dllexport) Session* realface_xmax_start(
    const char* token, const char* prompt, const char* reference,
    const char* camera, char* error,
    int capacity) {
  Apartment apartment;
  try {
    auto session = std::make_unique<Session>(token, camera);
    auto conditions = xmax::realtime_context{prompt, std::nullopt};
    if (*reference != '\0') conditions.reference_path = reference;
    session->remote =
        session->realtime.start_generation(session->local, conditions);
    return session.release();
  } catch (const std::exception& exception) {
    WriteError(error, capacity, exception);
    return nullptr;
  }
}

extern "C" __declspec(dllexport) const uint8_t* realface_xmax_frame(
    Session* session, int remote, int* length) {
  Apartment apartment;
  *length = 0;
  try {
    auto frame = session->realtime.acquire_stream_frame(
        remote ? *session->remote : session->local);
    if (!frame.get()) return nullptr;
    const auto timestamp = frame.view().timestamp_us;
    if (session->timestamps[remote] == timestamp) return nullptr;
    session->jpeg = EncodeJpeg(frame);
    session->timestamps[remote] = timestamp;
    *length = static_cast<int>(session->jpeg.size());
    return session->jpeg.data();
  } catch (const std::exception&) {
    *length = -1;
    return nullptr;
  }
}

extern "C" __declspec(dllexport) void realface_xmax_stop(Session* session) {
  Apartment apartment;
  try {
    session->realtime.close();
  } catch (const std::exception&) {
    // Destruction still releases the controller if explicit shutdown fails.
  }
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
