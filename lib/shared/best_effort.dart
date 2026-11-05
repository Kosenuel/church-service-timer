import 'package:flutter/foundation.dart';

/// Runs a cleanup step whose failure must not interrupt the caller, such as
/// telling a peer that has already disconnected. Failures are expected in
/// those situations, so they are reported only in debug builds, by type and
/// never with raw error text.
Future<bool> bestEffort(String step, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (kDebugMode)
      debugPrint('Best-effort $step failed: ${error.runtimeType}');
    return false;
  }
}
