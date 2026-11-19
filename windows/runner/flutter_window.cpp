#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <utility>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "church_service_timer/window",
          &flutter::StandardMethodCodec::GetInstance());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::AcceptDroppedFiles() {
  HWND window = GetHandle();
  if (window != nullptr) {
    DragAcceptFiles(window, TRUE);
  }
}

void FlutterWindow::OnFilesDropped(HDROP drop) noexcept {
  // Called from the message handler, which must not throw.
  try {
    flutter::EncodableList paths;
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      // The length excludes the closing null, which the buffer needs.
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      std::wstring path(static_cast<size_t>(length) + 1, L'\0');
      DragQueryFileW(drop, i, path.data(), length + 1);
      // A path that cannot be read is still counted, as an empty one, so
      // that the app sees how many things were dropped.
      paths.push_back(flutter::EncodableValue(Utf8FromUtf16(path.c_str())));
    }
    if (window_channel_ && !paths.empty()) {
      window_channel_->InvokeMethod(
          "filesDropped",
          std::make_unique<flutter::EncodableValue>(std::move(paths)));
    }
  } catch (...) {
  }
  DragFinish(drop);
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DROPFILES:
      OnFilesDropped(reinterpret_cast<HDROP>(wparam));
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
