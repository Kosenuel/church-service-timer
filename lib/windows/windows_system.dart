import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/windows/secret_vault.dart';
import 'package:church_service_timer/windows/win32_api.dart' as win32;
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:flutter/foundation.dart';

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
  @override
  void raise() => _quietly(() => win32.raiseWindow(win32.appWindow()), null);
  @override
  String description() => 'Windows PC · ${Platform.operatingSystemVersion}';
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
