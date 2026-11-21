/// Settings › About › Check for updates automatically, and what the last
/// automatic check found.
library;

import 'package:church_service_timer/domain/core.dart';

/// Kept on this device only: never in backups or program files, so a
/// restored backup neither turns the check on nor brings back an old
/// answer.
class AutoUpdateSettings {
  /// Off unless the operator turns it on.
  bool enabled;

  /// When this device last asked GitHub (device clock, ms), whatever the
  /// answer; null before the first automatic check.
  int? checkedWall;

  /// The newer version (x.y.z) the last automatic check found, or null.
  String? found;

  /// The version Not now hid on Live; a newer one is shown again.
  String? dismissed;

  AutoUpdateSettings({
    this.enabled = false,
    this.checkedWall,
    this.found,
    this.dismissed,
  });

  static final _version = RegExp(r'^\d{1,6}\.\d{1,6}\.\d{1,6}$');
  static String? _versionOf(Object? value) =>
      value is String && _version.hasMatch(value) ? value : null;

  /// Reads what was saved; anything unexpected is left at its default.
  factory AutoUpdateSettings.fromJson(Object? value) {
    if (value is! Map) return AutoUpdateSettings();
    final checked = value['checkedWall'];
    return AutoUpdateSettings(
      enabled: value['enabled'] == true,
      checkedWall: checked is int && checked >= 0 ? checked : null,
      found: _versionOf(value['found']),
      dismissed: _versionOf(value['dismissed']),
    );
  }

  Json toJson() => {
    'enabled': enabled,
    if (checkedWall != null) 'checkedWall': checkedWall,
    if (found != null) 'found': found,
    if (dismissed != null) 'dismissed': dismissed,
  };
}
