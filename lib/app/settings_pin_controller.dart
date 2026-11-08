import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

/// The optional Settings PIN: locked again whenever the app leaves the
/// foreground, with a one-time recovery code.
class SettingsPinController {
  final AppController app;
  SettingsPinController(this.app);

  /// True when a PIN is set and has not been entered since the app last left
  /// the foreground.
  bool get locked => app.state.settingsLock != null && !_unlocked;
  bool _unlocked = false;
  int _failures = 0;
  DateTime? retryAfter;

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    app.notifyChanged();
  }

  /// Five wrong PINs wait 30 seconds before the next try.
  Future<bool> unlock(String pin) async {
    final saved = app.state.settingsLock;
    if (saved == null) return true;
    final wait = retryAfter;
    if (wait != null && DateTime.now().isBefore(wait)) return false;
    if (await saved.checkPin(pin)) {
      _failures = 0;
      retryAfter = null;
      _unlocked = true;
      app.notifyChanged();
      return true;
    }
    _failures++;
    if (_failures >= 5) {
      _failures = 0;
      retryAfter = DateTime.now().add(const Duration(seconds: 30));
    }
    app.notifyChanged();
    return false;
  }

  /// Sets or replaces the PIN and returns the new one-time recovery code.
  Future<String?> setPin(String pin) async {
    require(SettingsLock.validPin(pin), 'Use 4 to 8 digits.');
    require(!locked, 'Enter the current PIN first.');
    final recovery = SettingsLock.newRecoveryCode();
    final next = await SettingsLock.create(pin, recovery);
    if (!await app.commit((draft, _) => draft.settingsLock = next)) return null;
    _unlocked = true;
    return recovery;
  }

  Future<bool> removePin() async {
    require(!locked, 'Enter the current PIN first.');
    return app.commit((draft, _) => draft.settingsLock = null);
  }

  /// The recovery code works once: it removes the PIN so a new one can be set.
  Future<bool> recover(String code) async {
    final saved = app.state.settingsLock;
    if (saved == null || !await saved.checkRecovery(code)) return false;
    final ok = await app.commit((draft, _) => draft.settingsLock = null);
    if (ok) {
      _unlocked = false;
      _failures = 0;
      retryAfter = null;
    }
    return ok;
  }
}
