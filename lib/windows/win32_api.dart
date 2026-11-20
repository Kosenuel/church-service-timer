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
  // GWL_STYLE (-16) becomes WS_POPUP (no title bar or borders) with
  // WS_CLIPCHILDREN. WS_VISIBLE (0x10000000) is kept as it is: taking it
  // off a window that is already showing leaves a picture on the screen
  // that never changes again.
  final style = _getWindowLongPtr(window, -16);
  final wanted = 0x80000000 | 0x02000000 | (style & 0x10000000);
  // Windows adds WS_CLIPSIBLINGS (0x04000000) to every top-level window.
  final restyle = (style & 0xFFFFFFFF & ~0x04000000) != wanted;
  if (restyle) _setWindowLongPtr(window, -16, wanted);
  _setWindowPos(
    window,
    topmost ? -1 : 0, // HWND_TOPMOST : HWND_TOP
    rect[0],
    rect[1],
    rect[2] - rect[0],
    rect[3] - rect[1],
    // SWP_NOACTIVATE, and SWP_FRAMECHANGED only when the style changed.
    0x0010 | (restyle ? 0x0020 : 0),
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

// ---- The app window, full screen -------------------------------------------

final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetWindowRect');

/// The window's style before [enterFullScreen] changed it.
int? _styleBeforeFullScreen;

/// Makes the app window a borderless one covering the monitor most of it
/// is on, as [fillScreen] does for the stage window. False, with nothing
/// changed, when the window or its screen could not be read.
bool enterFullScreen(int window) {
  if (window == 0 || _styleBeforeFullScreen != null) return false;
  // GWL_STYLE (-16); 0 means the read failed.
  final style = _getWindowLongPtr(window, -16);
  if (style == 0) return false;
  final rect = calloc<Int32>(4);
  List<int>? screen;
  try {
    if (_getWindowRect(window, rect) == 0) return false;
    var most = 0;
    for (final monitor in displayMonitors()) {
      final width =
          (rect[2] < monitor[2] ? rect[2] : monitor[2]) -
          (rect[0] > monitor[0] ? rect[0] : monitor[0]);
      final height =
          (rect[3] < monitor[3] ? rect[3] : monitor[3]) -
          (rect[1] > monitor[1] ? rect[1] : monitor[1]);
      if (width > 0 && height > 0 && width * height > most) {
        most = width * height;
        screen = monitor;
      }
    }
  } finally {
    calloc.free(rect);
  }
  if (screen == null) return false;
  _styleBeforeFullScreen = style;
  fillScreen(window, screen, topmost: false);
  return true;
}

/// Undoes [enterFullScreen]: the style it found, then the place the
/// window had ([frame], and whether it was [maximised]). False when the
/// window was not full screen or that place is on no screen any more; the
/// frame is given back either way.
bool leaveFullScreen(int window, List<int> frame, {required bool maximised}) {
  final style = _styleBeforeFullScreen;
  if (window == 0 || style == null) return false;
  _styleBeforeFullScreen = null;
  // Without WS_MAXIMIZE (0x01000000): the placement below maximises the
  // window again, which Windows skips for one it believes is maximised.
  _setWindowLongPtr(window, -16, style & ~0x01000000);
  final placed = restoreWindowPlacement(window, frame, maximised: maximised);
  // SWP_NOSIZE, SWP_NOMOVE, SWP_NOZORDER (0x4), SWP_NOACTIVATE and
  // SWP_FRAMECHANGED: redraw the title bar and borders for the style.
  _setWindowPos(
    window,
    0,
    0,
    0,
    0,
    0,
    0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020,
  );
  return placed;
}

// ---- The notification-area icon -------------------------------------------
//
// One icon beside the Windows clock whose tooltip is the countdown. Windows
// knows it by the app window and [_trayIconId]; a click comes back to that
// window as [trayCallbackMessage], which the runner answers by bringing the
// window forward (windows/runner/win32_window.cpp). Nothing here can change
// a service.

final _shellNotifyIcon = _shell32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('Shell_NotifyIconW');
final _getModuleHandle = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('GetModuleHandleW');
final _loadImage = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, Pointer<Utf16>, Uint32, Int32, Int32, Uint32),
      int Function(int, Pointer<Utf16>, int, int, int, int)
    >('LoadImageW');
final _getSystemMetrics = _user32
    .lookupFunction<Int32 Function(Int32), int Function(int)>(
      'GetSystemMetrics',
    );

/// The message Windows sends to the app window when the icon is clicked:
/// WM_APP (0x8000) + 0x3C7, with the mouse message in `lParam`. The same
/// number is written in windows/runner/win32_window.cpp; change both
/// together.
const trayCallbackMessage = 0x83C7;

/// The icon's number within the app window. There is only one.
const _trayIconId = 1;

/// IDI_APP_ICON in windows/runner/resource.h: the app's own icon.
const _appIconResource = 101;

/// `sizeof(NOTIFYICONDATAW)` on 64-bit Windows, the only kind the app is
/// built for. Windows reads the size first and refuses a wrong one.
const notifyIconDataSize = 976;

/// A `NOTIFYICONDATAW` for 64-bit Windows, as little-endian bytes.
///
/// The offsets, from shellapi.h with the usual alignment (a handle is 8
/// bytes and starts on a multiple of 8):
///
/// | offset | size | field                                    |
/// |-------:|-----:|------------------------------------------|
/// |      0 |    4 | `DWORD cbSize` (976)                     |
/// |      4 |    4 | padding                                  |
/// |      8 |    8 | `HWND hWnd`                              |
/// |     16 |    4 | `UINT uID`                               |
/// |     20 |    4 | `UINT uFlags`                            |
/// |     24 |    4 | `UINT uCallbackMessage`                  |
/// |     28 |    4 | padding                                  |
/// |     32 |    8 | `HICON hIcon`                            |
/// |     40 |  256 | `WCHAR szTip[128]` (UTF-16, ends with 0) |
/// |    296 |    4 | `DWORD dwState`                          |
/// |    300 |    4 | `DWORD dwStateMask`                      |
/// |    304 |  512 | `WCHAR szInfo[256]`                      |
/// |    816 |    4 | `UINT uTimeout` / `uVersion`             |
/// |    820 |  128 | `WCHAR szInfoTitle[64]`                  |
/// |    948 |    4 | `DWORD dwInfoFlags`                      |
/// |    952 |   16 | `GUID guidItem`                          |
/// |    968 |    8 | `HICON hBalloonIcon`                     |
///
/// Everything after `szTip` stays zero: the app shows no balloon and
/// hides nothing. [flags] says which of the message, icon and tip fields
/// Windows should read. A [tip] longer than 127 UTF-16 units is cut
/// short, never in the middle of a character.
///
/// This makes no Windows call, so it runs (and is tested) anywhere.
Uint8List notifyIconData({
  required int window,
  required int flags,
  int icon = 0,
  String tip = '',
}) {
  final bytes = Uint8List(notifyIconDataSize);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, notifyIconDataSize, Endian.little); // cbSize
  data.setInt64(8, window, Endian.little); // hWnd
  data.setUint32(16, _trayIconId, Endian.little); // uID
  data.setUint32(20, flags, Endian.little); // uFlags
  data.setUint32(24, trayCallbackMessage, Endian.little); // uCallbackMessage
  data.setInt64(32, icon, Endian.little); // hIcon
  var units = tip.codeUnits;
  if (units.length > 127) {
    units = units.sublist(0, 127);
    // Do not leave the first half of a two-unit character at the end.
    if (units.last >= 0xD800 && units.last <= 0xDBFF) units.removeLast();
  }
  for (var i = 0; i < units.length; i++) {
    data.setUint16(40 + i * 2, units[i], Endian.little); // szTip
  }
  return bytes;
}

const _nimAdd = 0, _nimModify = 1, _nimDelete = 2;
const _nifMessage = 0x1, _nifIcon = 0x2, _nifTip = 0x4;

bool _notifyIcon(int message, Uint8List data) {
  final native = calloc<Uint8>(data.length);
  try {
    native.asTypedList(data.length).setAll(0, data);
    return _shellNotifyIcon(message, native) != 0;
  } finally {
    calloc.free(native);
  }
}

/// The app's icon at the size the notification area uses. It is the copy
/// Windows shares within the program, so it is never freed here. 0 if it
/// could not be loaded; the icon is then an empty space with the tooltip.
int _smallAppIcon() => _loadImage(
  _getModuleHandle(nullptr), // this program's own resources
  Pointer.fromAddress(_appIconResource), // MAKEINTRESOURCE(IDI_APP_ICON)
  1, // IMAGE_ICON
  _getSystemMetrics(49), // SM_CXSMICON
  _getSystemMetrics(50), // SM_CYSMICON
  0x8000, // LR_SHARED
);

/// The window the icon was added for, or 0 while there is no icon.
int _trayWindow = 0;

/// Shows the notification-area icon with [tip] as its tooltip: adds it if
/// it is not there, and otherwise changes only the text, which does not
/// flicker. False when Windows refused (no window yet, or no taskbar to
/// put it on).
///
/// If Windows no longer knows the icon (Explorer restarted, which empties
/// the notification area), changing the text fails and the icon is added
/// again.
bool showTrayIcon(int window, String tip) {
  if (window == 0) return false;
  if (_trayWindow == window &&
      _notifyIcon(
        _nimModify,
        notifyIconData(window: window, flags: _nifTip, tip: tip),
      )) {
    return true;
  }
  if (_trayWindow != 0) removeTrayIcon();
  final added = _notifyIcon(
    _nimAdd,
    notifyIconData(
      window: window,
      flags: _nifMessage | _nifIcon | _nifTip,
      icon: _smallAppIcon(),
      tip: tip,
    ),
  );
  if (added) _trayWindow = window;
  return added;
}

/// Takes the icon away. Does nothing when there is none.
void removeTrayIcon() {
  final window = _trayWindow;
  if (window == 0) return;
  _trayWindow = 0;
  _notifyIcon(_nimDelete, notifyIconData(window: window, flags: 0));
}
