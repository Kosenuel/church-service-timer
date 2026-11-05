import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/warning_notifications.dart';
import 'package:church_service_timer/domain/domain.dart';

/// Schedules phone warning notifications from the saved service state and
/// tracks Android notification permission, sound and precise-alarm status.
class PhoneWarningScheduler {
  final AppController app;
  PhoneWarningScheduler(this.app);

  Json status = {'enabled': false, 'exact': false, 'sound': false};
  String? error;

  Future<void> sync({Session? previous}) async {
    try {
      final s = app.state.session;
      final newlySeen =
          previous != null &&
              previous.id == s.id &&
              previous.index == s.index &&
              s.warningNotice != null &&
              s.warningNotice != previous.warningNotice
          ? s.warningSeen.toSet().difference(previous.warningSeen.toSet())
          : <int>{};
      await app.port.syncWarnings(
        warningNotificationPlan(
          s,
          app.now,
          newlySeen: newlySeen,
          clearSeconds: app.state.notificationClearSeconds,
        ),
      );
      status = await app.port.notificationStatus();
      error = null;
    } catch (e) {
      error = 'Phone warnings could not be scheduled: $e';
    }
  }

  Future<void> enable() async {
    try {
      await app.port.enableNotifications();
      await sync();
    } catch (e) {
      error = 'Could not enable notifications: $e';
    }
    app.notifyChanged();
  }
}
