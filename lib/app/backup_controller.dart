import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';

/// Restoring a backup, and the sealed passwords a backup may carry.
class BackupController {
  final AppController app;
  BackupController(this.app);

  Future<bool> restore(AppState restored) async {
    try {
      await NativeDisplayFonts.prepareState(restored);
    } catch (e) {
      app.error = 'Backup not restored: $e';
      app.notifyChanged();
      return false;
    }
    final saved = await app.commit((draft, at) {
      require(
        !draft.session.active && draft.session.phase != 'ready',
        'End or cancel the loaded service before restoring a backup.',
      );
      for (final t in restored.templates) {
        validateTimelinePixels(t);
      }
      for (final cue in restored.stageCues) {
        validateLayout(cue);
      }
      validateLayout(restored.defaults.end);
      for (final cue in restored.defaults.cues) {
        validateLayout(cue);
      }
      for (final warning in restored.defaults.warnings) {
        validateLayout(warning.cue);
      }
      if (restored.defaults.zero != null)
        validateLayout(restored.defaults.zero!);
      draft.templates = restored.templates;
      draft.defaults = restored.defaults;
      draft.reports = restored.reports;
      draft.stageCues = restored.stageCues;
      draft.quickMessages = restored.quickMessages;
      draft.clockFormat = restored.clockFormat;
      draft.clockBlink = restored.clockBlink;
      draft.pixelShape = restored.pixelShape;
      draft.groupTemplates = restored.groupTemplates;
      draft.churchName = restored.churchName;
      draft.churchBanner = restored.churchBanner;
      draft.churchLogo = restored.churchLogo;
      draft.themeId = restored.themeId;
      draft.keepScreenAwake = restored.keepScreenAwake;
      draft.notificationClearSeconds = restored.notificationClearSeconds;
      draft.printPreferences = restored.printPreferences;
      draft.editDrafts.clear();
      draft.session = Session(
        id: 'restored-${at.wall}',
        anchor: at,
        revision: draft.session.revision + 1,
      );
    });
    if (saved) {
      app.simulator.clear();
      app.notifyChanged();
    }
    return saved;
  }

  /// Saved passwords on this phone that a backup may carry, sealed:
  /// the LED sign's device password and its Wi-Fi reconnect details.
  /// Paired-device approvals are never exported.
  Future<Map<String, dynamic>> secrets() async {
    final id = app.hardware.rememberedId;
    if (id.isEmpty) return {};
    final device = await app.port.savedDisplayPassword(id);
    final wifi = await app.port.signWifiProfile(id);
    final wifiPassword = await app.port.savedDisplayPassword('wifi:$id');
    return {
      'display': {
        'id': id,
        'name': app.hardware.rememberedName,
        'devicePassword': ?device,
        if ((wifi['ssid'] as String? ?? '').isNotEmpty)
          'wifi': {
            'ssid': wifi['ssid'],
            'security': wifi['security'] ?? 'wpa2',
            'bssid': wifi['bssid'] ?? '',
            'password': ?wifiPassword,
          },
      },
    };
  }

  bool hasSecrets(Map<String, dynamic> secrets) {
    final d = secrets['display'];
    return d is Map && (d['devicePassword'] != null || d['wifi'] != null);
  }

  /// Writes restored passwords back to this phone's encrypted storage.
  /// Returns how many were restored.
  Future<int> restoreSecrets(Map<String, dynamic> secrets) async {
    final d = secrets['display'];
    if (d is! Map || d['id'] is! String || (d['id'] as String).isEmpty)
      return 0;
    final id = d['id'] as String;
    var count = 0;
    if (d['devicePassword'] is String) {
      await app.port.saveDisplayPassword(id, d['devicePassword'] as String);
      count++;
    }
    final wifi = d['wifi'];
    if (wifi is Map && wifi['ssid'] is String) {
      await app.port.saveSignWifiProfile({
        'id': id,
        'ssid': wifi['ssid'],
        'security': wifi['security'] ?? 'wpa2',
        'bssid': wifi['bssid'] ?? '',
        'password': wifi['password'],
      });
      count++;
    }
    return count;
  }
}
