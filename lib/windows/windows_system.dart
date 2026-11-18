import 'dart:async';
import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/windows/secret_vault.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:church_service_timer/windows/win32_api.dart' as win32;
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// [DesktopSystem] on a real Windows PC. Every call is one line into
/// win32_api.dart, and a failure there never stops the service: asking
/// Windows to stay awake or flash the taskbar is a courtesy.
class WindowsSystem implements DesktopSystem {
  const WindowsSystem();

  T _quietly<T>(T Function() call, T otherwise) {
    try {
      return call();
    } catch (_) {
      return otherwise;
    }
  }

  @override
  bool open(String target) => _quietly(() => win32.shellOpen(target), false);
  @override
  void keepAwake({required bool system, required bool display}) => _quietly(
    () => win32.setExecutionState(system: system, display: display),
    null,
  );
  @override
  Json power() => _quietly(win32.powerStatus, <String, dynamic>{});
  @override
  void flash() => _quietly(() => win32.flashWindow(win32.appWindow()), null);
  static bool _notifierReady = false;
  static LocalNotification? _shown;
  static Timer? _clear;

  @override
  void notify(String title, String body, {int clearSeconds = 30}) {
    unawaited(() async {
      try {
        if (!_notifierReady) {
          // Windows only shows notifications from an app it can find in
          // the Start menu, so this adds a shortcut there if none exists.
          await localNotifier.setup(appName: 'Church Service Timer');
          _notifierReady = true;
        }
        // One warning at a time, like the phone: a new one replaces the
        // last instead of piling up.
        _clear?.cancel();
        await _shown?.close();
        final notification = LocalNotification(
          title: title,
          body: body,
          silent: true,
        );
        _shown = notification;
        await notification.show();
        if (clearSeconds > 0) {
          _clear = Timer(Duration(seconds: clearSeconds), () {
            if (_shown == notification) {
              unawaited(notification.close().catchError((_) {}));
              _shown = null;
            }
          });
        }
      } catch (_) {
        // The taskbar flash has already happened; a notification that
        // Windows would not show must not disturb the service.
      }
    }());
  }

  @override
  void raise() => _quietly(() => win32.raiseWindow(win32.appWindow()), null);
  @override
  String description() => 'Windows PC · ${Platform.operatingSystemVersion}';
}

class _ChildProcess implements StageChild {
  final Process process;
  _ChildProcess(this.process);
  @override
  Future<void> get exited => process.exitCode;
  @override
  void kill() => process.kill();
}

/// Lists the PC's screens and starts the second copy of the app that
/// draws the stage window.
class WindowsStageLauncher implements StageOutputLauncher {
  const WindowsStageLauncher();
  @override
  List<StageMonitor> monitors() {
    final rects = win32.displayMonitors();
    return [
      for (var i = 0; i < rects.length; i++)
        (
          index: i,
          rect: rects[i],
          primary: rects[i][0] == 0 && rects[i][1] == 0,
        ),
    ];
  }

  @override
  Future<StageChild> launch(List<String> arguments) async => _ChildProcess(
    await Process.start(Platform.resolvedExecutable, arguments),
  );
}

/// Secrets sealed by Windows for this user account on this PC (DPAPI).
class DpapiProtector implements SecretProtector {
  const DpapiProtector();
  @override
  Uint8List protect(Uint8List plain, Uint8List entropy) =>
      win32.dpapiProtect(plain, entropy);
  @override
  Uint8List unprotect(Uint8List cipher, Uint8List entropy) =>
      win32.dpapiUnprotect(cipher, entropy);
}
