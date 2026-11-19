#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (stage_output && stage_has_rect) {
    if (!window.CreateFullScreen(L"Stage output \u00b7 Church Service Timer",
                                 stage_rect, stage_topmost)) {
      return EXIT_FAILURE;
    }
  } else {
    // The app moves the window back to where it was last time once it has
    // started (lib/windows/window_memory.dart); this is the first-run size.
    Win32Window::Point origin(80, 60);
    Win32Window::Size size(1280, 800);
    if (!window.Create(L"Church Service Timer", origin, size)) {
      return EXIT_FAILURE;
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
