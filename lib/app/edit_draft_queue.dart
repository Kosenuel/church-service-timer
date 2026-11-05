import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

/// Batches unsaved program and message edits into the saved state, so a
/// draft survives navigation or a restart. Writes go through the normal
/// [AppController.commit] path and wait while a service report is saving.
class EditDraftQueue {
  final AppController app;
  EditDraftQueue(this.app);

  final Map<String, Json?> _writes = {};
  Timer? _timer;
  Future<void>? _flush;
  String? error;

  void queue(String key, Json? value) {
    _writes[key] = value;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    return _flush ??= _flushAll().whenComplete(() => _flush = null);
  }

  Future<void> _flushAll() async {
    while (_writes.isNotEmpty && !app.disposed && app.ready) {
      if (app.busy) await app.pendingWrite;
      if (app.disposed) return;
      if (app.reportSavePending) {
        _timer = Timer(const Duration(milliseconds: 600), flush);
        return;
      }
      final pending = Map<String, Json?>.from(_writes);
      final ok = await app.commit((draft, _) {
        for (final entry in pending.entries) {
          if (entry.value == null) {
            draft.editDrafts.remove(entry.key);
          } else {
            draft.editDrafts[entry.key] = entry.value!;
          }
        }
        readEditDrafts(draft.editDrafts);
      });
      if (!ok) {
        error = 'Draft could not be saved. Keep this screen open and retry.';
        if (!app.disposed) app.notifyChanged();
        return;
      }
      for (final entry in pending.entries) {
        if (identical(_writes[entry.key], entry.value))
          _writes.remove(entry.key);
      }
      error = null;
      if (!app.disposed) app.notifyChanged();
    }
  }

  void dispose() => _timer?.cancel();
}
