import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/seen_version.dart';

/// The "Updated to X · See what's new" notice on Live. The last version
/// the notice was dealt with is kept on this device only (`seenVersion`).
/// A new install records the running version without showing anything, a
/// downgrade records the lower version, and a newer running version is
/// shown once until it is dismissed or opened.
class WhatsNewNotice {
  final AppController app;
  WhatsNewNotice(this.app);

  SemanticVersion? get _running => SemanticVersion.tryParse(app.appVersion);

  /// Called once the app is ready: records the running version when
  /// there is no saved state at all (a new install), or when this version
  /// is older than the one seen. A saved state with nothing seen comes from
  /// a version before this notice existed, so the notice shows once.
  Future<void> start() async {
    final now = _running;
    if (now == null || app.corrupt || app.disposed) return;
    final seen = SemanticVersion.tryParse(app.state.seenVersion);
    if (seen == null ? !app.hadSavedState : now.compareTo(seen) < 0) {
      await markSeen();
    }
  }

  /// The running version for the notice, or null when it was seen or is
  /// not newer than the one seen.
  String? get notice {
    final now = _running;
    final seen = SemanticVersion.tryParse(app.state.seenVersion);
    if (now == null || app.corrupt) return null;
    // Nothing seen on an existing install: it was updated from a version
    // before this notice.
    if (seen == null) return app.hadSavedState ? now.toString() : null;
    return now.compareTo(seen) > 0 ? now.toString() : null;
  }

  /// Marks the running version as seen.
  Future<bool> markSeen() {
    final now = _running;
    if (now == null) return Future.value(false);
    return app.commit((draft, _) => draft.seenVersion = now.toString());
  }
}
