#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Reads the place the window was last closed at from window.json in the
// app's data folder: {"window":{"frame":[left,top,right,bottom],
// "maximised":bool}}. Returns false when there is none, it makes no sense,
// or no screen shows that area any more. A frame larger than its screen (a
// place saved by an earlier version that had grown) is brought back inside.
bool ReadSavedWindowPlace(RECT* frame, bool* maximised) {
  wchar_t base[MAX_PATH];
  DWORD length = GetEnvironmentVariableW(L"APPDATA", base, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }
  std::wstring path = std::wstring(base) +
                      L"\\I-Proton\\Church Service Timer\\window.json";
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  char buffer[4096];
  DWORD read = 0;
  BOOL ok = ReadFile(file, buffer, sizeof(buffer) - 1, &read, nullptr);
  CloseHandle(file);
  if (!ok || read == 0) {
    return false;
  }
  buffer[read] = 0;
  std::string text(buffer);

  size_t window_at = text.find("\"window\"");
  if (window_at == std::string::npos) {
    return false;
  }
  size_t end = text.find('}', window_at);
  std::string place = text.substr(
      window_at, end == std::string::npos ? std::string::npos : end - window_at);
  size_t frame_at = place.find("\"frame\"");
  if (frame_at == std::string::npos) {
    return false;
  }
  size_t open = place.find('[', frame_at);
  if (open == std::string::npos) {
    return false;
  }
  long left = 0, top = 0, right = 0, bottom = 0;
  if (sscanf_s(place.c_str() + open, "[ %ld , %ld , %ld , %ld", &left, &top,
               &right, &bottom) != 4) {
    return false;
  }
  if (right - left < 200 || bottom - top < 200) {
    return false;
  }
  RECT wanted = {left, top, right, bottom};
  HMONITOR monitor = MonitorFromRect(&wanted, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) {
    return false;
  }
  MONITORINFO info;
  info.cbSize = sizeof(info);
  if (GetMonitorInfo(monitor, &info)) {
    const RECT& work = info.rcWork;
    LONG width = wanted.right - wanted.left;
    LONG height = wanted.bottom - wanted.top;
    if (width > work.right - work.left) width = work.right - work.left;
    if (height > work.bottom - work.top) height = work.bottom - work.top;
    if (wanted.left + width > work.right) wanted.left = work.right - width;
    if (wanted.top + height > work.bottom) wanted.top = work.bottom - height;
    if (wanted.left < work.left) wanted.left = work.left;
    if (wanted.top < work.top) wanted.top = work.top;
    wanted.right = wanted.left + width;
    wanted.bottom = wanted.top + height;
  }
  *frame = wanted;
  size_t maximised_at = place.find("\"maximised\"");
  *maximised = maximised_at != std::string::npos &&
               place.compare(maximised_at, 16, "\"maximised\":true") == 0;
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // The stage window (lib/windows/stage_output.dart) is started with the
  // screen it must cover. It is made borderless on that screen from the
  // start, instead of being moved and restyled after the app has begun.
  bool stage_output = false;
  bool stage_topmost = false;
  bool stage_has_rect = false;
  RECT stage_rect = {0, 0, 0, 0};
  for (const std::string& argument : command_line_arguments) {
    if (argument == "--stage-output") {
      stage_output = true;
    } else if (argument == "--topmost") {
      stage_topmost = true;
    } else if (argument.rfind("--rect=", 0) == 0) {
      long left = 0, top = 0, right = 0, bottom = 0;
      if (sscanf_s(argument.c_str() + 7, "%ld,%ld,%ld,%ld", &left, &top,
                   &right, &bottom) == 4 &&
          right - left >= 200 && bottom - top >= 200) {
        stage_rect = {left, top, right, bottom};
        stage_has_rect = true;
      }
    }
  }

  // Where the window was last time (lib/windows/window_memory.dart saves
  // it). It is opened there from the start: moving it after Flutter has
  // begun, onto a screen with a different scale, left the app drawn in a
  // corner of an oversized window. The app is told, so it does not move
  // the window again.
  RECT saved_frame = {0, 0, 0, 0};
  bool saved_maximised = false;
  const bool has_saved_place =
      !stage_output && ReadSavedWindowPlace(&saved_frame, &saved_maximised);
  if (has_saved_place) {
    command_line_arguments.push_back("--window-placed");
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (stage_output && stage_has_rect) {
    if (!window.CreateFullScreen(L"Stage output \u00b7 Church Service Timer",
                                 stage_rect, stage_topmost)) {
      return EXIT_FAILURE;
    }
  } else {
    bool created = false;
    if (has_saved_place) {
      created = window.CreateAt(L"Church Service Timer", saved_frame,
                                saved_maximised);
    }
    if (!created) {
      // The first-run size.
      Win32Window::Point origin(80, 60);
      Win32Window::Size size(1280, 800);
      if (!window.Create(L"Church Service Timer", origin, size)) {
        return EXIT_FAILURE;
      }
    }
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
