// The few Windows calls the app needs, bound directly with dart:ffi.
//
// Nothing here is loaded until it is first used, so importing this file on
// Android or in tests is harmless; calling into it anywhere but Windows
// throws. Everything that can be decided without Windows lives in the other
// files of this folder, behind interfaces the tests drive.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _user32 = DynamicLibrary.open('user32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');
final _crypt32 = DynamicLibrary.open('crypt32.dll');

// ---- Time and power -------------------------------------------------------

final _getTickCount64 = _kernel32
    .lookupFunction<Uint64 Function(), int Function()>('GetTickCount64');

/// Milliseconds since Windows started. Unlike the "unbiased" interrupt
/// time, this keeps counting while the PC sleeps or hibernates, which is
/// what a running service needs.
int tickCount64() => _getTickCount64();

final _setThreadExecutionState = _kernel32
    .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
      'SetThreadExecutionState',
    );

const _esContinuous = 0x80000000;
const _esSystemRequired = 0x00000001;
const _esDisplayRequired = 0x00000002;

/// Asks Windows not to sleep ([system]) or turn the screen off ([display])
/// until this is called again. Applies to the calling thread, which for
/// the app is the one that lives as long as the window.
void setExecutionState({required bool system, required bool display}) {
  _setThreadExecutionState(
    _esContinuous |
        (system ? _esSystemRequired : 0) |
        (display ? _esDisplayRequired : 0),
  );
}

final _getSystemPowerStatus = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Uint8>),
      int Function(Pointer<Uint8>)
    >('GetSystemPowerStatus');

/// Battery level (%) and whether on mains; empty for a PC with no battery.
Map<String, dynamic> powerStatus() {
  final status = calloc<Uint8>(12);
  try {
    if (_getSystemPowerStatus(status) == 0) return {};
    final line = status[0], flag = status[1], percent = status[2];
    if (flag == 255 || flag & 128 != 0) return {};
    return {if (percent <= 100) 'level': percent, 'charging': line == 1};
  } finally {
    calloc.free(status);
  }
}

// ---- Opening things with their Windows handler ----------------------------

final _shellExecute = _shell32
    .lookupFunction<
      IntPtr Function(
        IntPtr,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Int32,
      ),
      int Function(
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
      )
    >('ShellExecuteW');

/// Opens [target] (a web address, `mailto:` or `ms-settings:` link) with
/// whatever Windows has registered for it. Never used for file paths.
bool shellOpen(String target) {
  final verb = 'open'.toNativeUtf16();
  final file = target.toNativeUtf16();
  try {
    // Values above 32 mean success.
    return _shellExecute(0, verb, file, nullptr, nullptr, 1) > 32;
  } finally {
    calloc.free(verb);
    calloc.free(file);
  }
}

// ---- Secrets (DPAPI) ------------------------------------------------------

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _CryptDart =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
final _cryptProtectData = _crypt32.lookupFunction<_CryptNative, _CryptDart>(
  'CryptProtectData',
);
final _cryptUnprotectData = _crypt32.lookupFunction<_CryptNative, _CryptDart>(
  'CryptUnprotectData',
);
final _localFree = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('LocalFree');

const _cryptprotectUiForbidden = 0x1;

Uint8List _crypt(_CryptDart call, Uint8List input, Uint8List entropy) {
  final inBytes = calloc<Uint8>(input.isEmpty ? 1 : input.length);
  final entropyBytes = calloc<Uint8>(entropy.isEmpty ? 1 : entropy.length);
  final inBlob = calloc<_DataBlob>();
  final entropyBlob = calloc<_DataBlob>();
  final outBlob = calloc<_DataBlob>();
  try {
    inBytes.asTypedList(input.length).setAll(0, input);
    entropyBytes.asTypedList(entropy.length).setAll(0, entropy);
    inBlob.ref
      ..cbData = input.length
      ..pbData = inBytes;
    entropyBlob.ref
      ..cbData = entropy.length
      ..pbData = entropyBytes;
    final ok = call(
      inBlob,
      nullptr,
      entropyBlob,
      nullptr,
      nullptr,
      _cryptprotectUiForbidden,
      outBlob,
    );
    if (ok == 0) throw StateError('Windows could not protect this secret.');
    final out = Uint8List.fromList(
      outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
    );
    outBlob.ref.pbData
        .asTypedList(outBlob.ref.cbData)
        .fillRange(0, outBlob.ref.cbData, 0);
    _localFree(outBlob.ref.pbData.cast());
    return out;
  } finally {
    inBytes.asTypedList(input.length).fillRange(0, input.length, 0);
    calloc.free(inBytes);
    calloc.free(entropyBytes);
    calloc.free(inBlob);
    calloc.free(entropyBlob);
    calloc.free(outBlob);
  }
}

/// Encrypts [plain] so only this Windows user account on this PC can read
/// it back. [entropy] must be the same when reading.
Uint8List dpapiProtect(Uint8List plain, Uint8List entropy) =>
    _crypt(_cryptProtectData, plain, entropy);
Uint8List dpapiUnprotect(Uint8List cipher, Uint8List entropy) =>
    _crypt(_cryptUnprotectData, cipher, entropy);

// ---- The app window -------------------------------------------------------

final _findWindowEx = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowExW');
final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
final _getCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
final _getWindowPlacement = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetWindowPlacement');
final _setWindowPlacement = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('SetWindowPlacement');
final _monitorFromRect = _user32
    .lookupFunction<
      IntPtr Function(Pointer<Int32>, Uint32),
      int Function(Pointer<Int32>, int)
    >('MonitorFromRect');
final _setWindowText = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>)
    >('SetWindowTextW');
final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );
final _showWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'ShowWindow',
    );
final _isIconic = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final _messageBeep = _user32
    .lookupFunction<Int32 Function(Uint32), int Function(int)>('MessageBeep');

final class _FlashInfo extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int uCount;
  @Uint32()
  external int dwTimeout;
}

final _flashWindowEx = _user32
    .lookupFunction<
      Int32 Function(Pointer<_FlashInfo>),
      int Function(Pointer<_FlashInfo>)
    >('FlashWindowEx');

/// The window class the Flutter runner registers (windows/runner).
const _runnerClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// This process's top-level window, or 0 before it exists.
int appWindow() {
  final name = _runnerClass.toNativeUtf16();
  final owner = calloc<Uint32>();
  try {
    final me = _getCurrentProcessId();
    var window = 0;
    for (var i = 0; i < 64; i++) {
      window = _findWindowEx(0, window, name, nullptr);
      if (window == 0) return 0;
      _getWindowThreadProcessId(window, owner);
      if (owner.value == me) return window;
    }
    return 0;
  } finally {
    calloc.free(name);
    calloc.free(owner);
  }
}

/// Where the window sits when it is neither minimised nor maximised, and
/// whether it is maximised: `[left, top, right, bottom]` in the units
/// Windows gave, to be handed back unchanged.
({List<int> frame, bool maximised})? windowPlacement(int window) {
  if (window == 0) return null;
  final data = calloc<Int32>(11);
  try {
    data[0] = 44;
    if (_getWindowPlacement(window, data) == 0) return null;
    return (
      frame: [data[7], data[8], data[9], data[10]],
      // SW_SHOWMAXIMIZED, or minimised from maximised.
      maximised: data[2] == 3 || (data[2] == 2 && data[1] & 2 != 0),
    );
  } finally {
    calloc.free(data);
  }
}

/// Puts the window back at [frame]. Returns false, changing nothing, when
/// no monitor shows that area any more (a projector that was unplugged).
bool restoreWindowPlacement(
  int window,
  List<int> frame, {
  required bool maximised,
}) {
  if (window == 0 || frame.length != 4) return false;
  final rect = calloc<Int32>(4);
  final data = calloc<Int32>(11);
  try {
    for (var i = 0; i < 4; i++) {
      rect[i] = frame[i];
    }
    // MONITOR_DEFAULTTONULL: nothing when the area is off every screen.
    if (_monitorFromRect(rect, 0) == 0) return false;
    data[0] = 44;
    if (_getWindowPlacement(window, data) == 0) return false;
    data[2] = maximised ? 3 : 1; // SW_SHOWMAXIMIZED : SW_SHOWNORMAL
    for (var i = 0; i < 4; i++) {
      data[7 + i] = frame[i];
    }
    return _setWindowPlacement(window, data) != 0;
  } finally {
    calloc.free(rect);
    calloc.free(data);
  }
}

void setWindowTitle(int window, String title) {
  if (window == 0) return;
  final text = title.toNativeUtf16();
  try {
    _setWindowText(window, text);
  } finally {
    calloc.free(text);
  }
}

/// Brings the window to the front, restoring it if minimised.
void raiseWindow(int window) {
  if (window == 0) return;
  if (_isIconic(window) != 0) _showWindow(window, 9); // SW_RESTORE
  _setForegroundWindow(window);
}

/// Flashes the taskbar button until the window is brought forward.
void flashWindow(int window) {
  if (window == 0) return;
  final info = calloc<_FlashInfo>();
  try {
    info.ref
      ..cbSize = sizeOf<_FlashInfo>()
      ..hwnd = window
      ..dwFlags =
          0x2 |
          0xC // FLASHW_TRAY | FLASHW_TIMERNOFG
      ..uCount = 0
      ..dwTimeout = 0;
    _flashWindowEx(info);
  } finally {
    calloc.free(info);
  }
}

/// The Windows "exclamation" sound, at the PC's own volume.
void warningBeep() => _messageBeep(0x30);

// ---- Screens, for the stage window ----------------------------------------

typedef _MonitorEnumNative =
    Int32 Function(IntPtr, IntPtr, Pointer<Int32>, IntPtr);
final _enumDisplayMonitors = _user32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Void>,
        Pointer<NativeFunction<_MonitorEnumNative>>,
        IntPtr,
      ),
      int Function(
        int,
        Pointer<Void>,
        Pointer<NativeFunction<_MonitorEnumNative>>,
        int,
      )
    >('EnumDisplayMonitors');
final _setWindowLongPtr = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, Int32, IntPtr),
      int Function(int, int, int)
    >('SetWindowLongPtrW');
final _setWindowPos = _user32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(int, int, int, int, int, int, int)
    >('SetWindowPos');

/// Every screen of the desktop as `[left, top, right, bottom]`, in the
/// order Windows reports them. The primary screen is the one at 0, 0.
List<List<int>> displayMonitors() {
  final found = <List<int>>[];
  final callback = NativeCallable<_MonitorEnumNative>.isolateLocal((
    int monitor,
    int dc,
    Pointer<Int32> rect,
    int data,
  ) {
    found.add([rect[0], rect[1], rect[2], rect[3]]);
    return 1;
  }, exceptionalReturn: 0);
  try {
    _enumDisplayMonitors(0, nullptr, callback.nativeFunction, 0);
  } finally {
    callback.close();
  }
  return found;
}

/// Makes the window a borderless one covering [rect] exactly.
void fillScreen(int window, List<int> rect, {required bool topmost}) {
  if (window == 0 || rect.length != 4) return;
  // GWL_STYLE = WS_POPUP: no title bar or borders. The runner shows the
  // window itself with the first frame.
  _setWindowLongPtr(window, -16, 0x80000000);
  _setWindowPos(
    window,
    topmost ? -1 : 0, // HWND_TOPMOST : HWND_TOP
    rect[0],
    rect[1],
    rect[2] - rect[0],
    rect[3] - rect[1],
    0x0020, // SWP_FRAMECHANGED
  );
}

// ---- The mini timer's window ----------------------------------------------

final _getWindowLongPtr = _user32
    .lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
      'GetWindowLongPtrW',
    );

/// The window's style before [pinWindow] changed it, to put back exactly.
int? _styleBeforePin;

/// Keeps the window above every other window ([onTop]) and greys out its
/// maximise button, or undoes both. It is not moved, resized or brought
/// forward. False when Windows refused.
bool pinWindow(int window, {required bool onTop}) {
  if (window == 0) return false;
  if (onTop) {
    // GWL_STYLE (-16): the window's style bits as they are now.
    final style = _styleBeforePin ??= _getWindowLongPtr(window, -16);
    // The same style without WS_MAXIMIZEBOX (0x00010000), so the small
    // window cannot be maximised from its title bar. A style of 0 means
    // the read failed, and the style is then left alone.
    if (style != 0) _setWindowLongPtr(window, -16, style & ~0x00010000);
  } else {
    final style = _styleBeforePin;
    _styleBeforePin = null;
    // Put the style back as it was found.
    if (style != null && style != 0) _setWindowLongPtr(window, -16, style);
  }
  // HWND_TOPMOST (-1) puts the window in the always-on-top band and
  // HWND_NOTOPMOST (-2) takes it out again. SWP_NOSIZE (0x1), SWP_NOMOVE
  // (0x2) and SWP_NOACTIVATE (0x10) leave size, place and focus alone;
  // SWP_FRAMECHANGED (0x20) makes Windows redraw the title bar for the
  // changed style.
  return _setWindowPos(
        window,
        onTop ? -1 : -2,
        0,
        0,
        0,
        0,
        0x0001 | 0x0002 | 0x0010 | 0x0020,
      ) !=
      0;
}
