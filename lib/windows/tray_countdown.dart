/// Decides what the icon in the Windows notification area shows.
///
/// While a service or quick timer runs, the icon's tooltip is the
/// countdown, for when the lyrics or slides program is in front of the
/// app. The icon only shows the time and brings the window forward when
/// clicked; it cannot change a service.
///
/// [put] is the one call into Windows: it shows the icon with that
/// tooltip (adding the icon, or changing its text), or takes the icon
/// away for null, and says whether Windows accepted. It is called only
/// when what should be showing differs from what is, so a text that
/// changes once a second costs one call a second and nothing flickers.
class TrayCountdown {
  final bool Function(String? tip) put;
  TrayCountdown(this.put);

  /// How many changes of text to let pass after Windows refused, before
  /// asking again: about ten seconds of a running countdown. Windows can
  /// take seconds to answer when the taskbar is not responding, and the
  /// timer must not wait for it every second.
  static const refusedPause = 10;

  bool _enabled = true, _closed = false;
  String? _wanted, _shown;
  int _pause = 0;

  /// Whether the operator wants the icon at all (a setting).
  bool get enabled => _enabled;
  set enabled(bool on) {
    _enabled = on;
    _pause = 0;
    _apply();
  }

  /// The countdown text as it is now, or null when nothing is running.
  void show(String? text) {
    if (text == _wanted) return;
    _wanted = text;
    _apply();
  }

  /// The app is closing: the icon goes and does not come back.
  void close() {
    _closed = true;
    _apply();
  }

  void _apply() {
    final target = _enabled && !_closed ? _wanted : null;
    if (target == _shown) return;
    if (target != null && _pause > 0) {
      _pause--;
      return;
    }
    var accepted = false;
    try {
      accepted = put(target);
    } catch (_) {
      // The icon is a courtesy; a failure must not disturb the service.
    }
    if (accepted || target == null) {
      // Taking the icon away is not tried twice: if Windows refused, it
      // has no icon to take.
      _shown = target;
    } else {
      _pause = refusedPause;
    }
  }
}
