#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace {

struct Frame {
  int width;
  int height;
  std::vector<uint8_t> rgba;
};

class OutputWindow {
 public:
  OutputWindow(int width, int height) {
    std::promise<bool> started;
    auto ready = started.get_future();
    thread_ = std::thread([this, width, height, &started] {
      Run(width, height, started);
    });
    ready.get();
  }

  ~OutputWindow() {
    if (const auto window = window_.load()) {
      PostMessageW(window, WM_CLOSE, 0, 0);
    }
    thread_.join();
  }

  bool IsOpen() const { return window_.load() != nullptr; }

  bool Submit(int width, int height, const uint8_t* rgba) {
    const auto window = window_.load();
    if (!window) return false;
    auto frame = std::make_shared<Frame>();
    frame->width = width;
    frame->height = height;
    const auto bytes = static_cast<size_t>(width) * height * 4;
    frame->rgba.assign(rgba, rgba + bytes);
    {
      std::lock_guard<std::mutex> lock(mutex_);
      latest_ = std::move(frame);
    }
    return InvalidateRect(window, nullptr, FALSE) != FALSE;
  }

 private:
  void Run(int width, int height, std::promise<bool>& started) {
    const auto instance = GetModuleHandleW(nullptr);
    constexpr wchar_t kClass[] = L"RealFaceAIBorderlessOutput";
    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kClass;
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      started.set_value(false);
      return;
    }

    RECT work_area{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
    const int x = work_area.left + std::max(0, static_cast<int>(
        (work_area.right - work_area.left - width) / 2));
    const int y = work_area.top + std::max(0, static_cast<int>(
        (work_area.bottom - work_area.top - height) / 2));
    const auto window = CreateWindowExW(
        WS_EX_APPWINDOW, kClass, L"RealFaceAI AI Output",
        WS_POPUP, x, y, width, height, nullptr, nullptr, instance, this);
    window_.store(window);
    started.set_value(window != nullptr);
    if (!window) return;
    ShowWindow(window, SW_SHOW);
    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }

  void Paint(HWND window) {
    PAINTSTRUCT paint{};
    const auto dc = BeginPaint(window, &paint);
    RECT bounds{};
    GetClientRect(window, &bounds);
    std::shared_ptr<const Frame> frame;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      frame = latest_;
    }
    if (frame) {
      struct {
        BITMAPINFOHEADER header;
        DWORD masks[3];
      } bitmap{};
      bitmap.header.biSize = sizeof(bitmap.header);
      bitmap.header.biWidth = frame->width;
      bitmap.header.biHeight = -frame->height;
      bitmap.header.biPlanes = 1;
      bitmap.header.biBitCount = 32;
      bitmap.header.biCompression = BI_BITFIELDS;
      bitmap.masks[0] = 0x000000ff;
      bitmap.masks[1] = 0x0000ff00;
      bitmap.masks[2] = 0x00ff0000;
      SetStretchBltMode(dc, COLORONCOLOR);
      StretchDIBits(dc, 0, 0, bounds.right, bounds.bottom, 0, 0, frame->width,
                    frame->height, frame->rgba.data(),
                    reinterpret_cast<const BITMAPINFO*>(&bitmap),
                    DIB_RGB_COLORS, SRCCOPY);
    } else {
      FillRect(dc, &bounds, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    }
    EndPaint(window, &paint);
  }

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto* data = reinterpret_cast<const CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(data->lpCreateParams));
    }
    auto* self = reinterpret_cast<OutputWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    switch (message) {
      case WM_NCHITTEST:
        if (DefWindowProcW(window, message, wparam, lparam) == HTCLIENT) {
          return HTCAPTION;
        }
        break;
      case WM_ERASEBKGND:
        return 1;
      case WM_PAINT:
        if (self) {
          self->Paint(window);
          return 0;
        }
        break;
      case WM_KEYDOWN:
        if (wparam == VK_ESCAPE) {
          DestroyWindow(window);
          return 0;
        }
        break;
      case WM_DESTROY:
        if (self) self->window_.store(nullptr);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  std::mutex mutex_;
  std::shared_ptr<const Frame> latest_;
  std::atomic<HWND> window_{nullptr};
  std::thread thread_;
};

std::unique_ptr<OutputWindow> output;

}  // namespace

extern "C" __declspec(dllexport) int realface_open_ai_output(int width,
                                                            int height) {
  if (width < 1 || width > 960 || height < 1 || height > 540) return 0;
  output.reset();
  output = std::make_unique<OutputWindow>(width, height);
  return output->IsOpen() ? 1 : 0;
}

extern "C" __declspec(dllexport) int realface_submit_ai_frame(
    int width, int height, const uint8_t* rgba) {
  if (!output || width < 1 || width > 960 || height < 1 || height > 540 ||
      !rgba) return 0;
  return output->Submit(width, height, rgba) ? 1 : 0;
}

extern "C" __declspec(dllexport) void realface_close_ai_output() {
  output.reset();
}
