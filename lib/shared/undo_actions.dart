import 'dart:async';
import 'dart:math' as math;
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

extension UndoActions on HomeState {
  void offerUndo(
    String label,
    Future<bool> Function() restore, {
    Duration duration = const Duration(seconds: 8),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        duration: duration,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (!await restore() && mounted)
              await showError(c.error ?? 'Could not restore the item.');
          },
        ),
      ),
    );
  }

  Future<void> deleteCueWithUndo(int index, TextLayout cue) async {
    if (!await c.deleteStageCue(index, cue) || !mounted) return;
    offerUndo(
      'Cue deleted',
      () => c.commit((draft, _) {
        require(draft.stageCues.length < 100, 'The cue list is full.');
        require(
          !draft.stageCues.any(
            (v) => v.toJson().toString() == cue.toJson().toString(),
          ),
          'This cue has already been restored.',
        );
        draft.stageCues.insert(math.min(index, draft.stageCues.length), cue);
      }),
    );
  }

  Future<void> saveWarningsWithUndo(DisplaySettings next) async {
    final before = c.state.defaults.warnings;
    final deleted = before
        .where((v) => !next.warnings.any((n) => n.seconds == v.seconds))
        .toList();
    if (!await c.setSharedWarnings(next.warnings)) {
      if (mounted) await showError(c.error ?? 'Could not save warnings.');
      return;
    }
    if (deleted.length == 1 &&
        next.warnings.length == before.length - 1 &&
        mounted) {
      final rule = deleted.single, position = before.indexOf(deleted.single);
      offerUndo(
        'Warning deleted',
        () => c.commit((draft, at) {
          final rules = [...draft.defaults.warnings];
          require(rules.length < 6, 'There are already six warnings.');
          require(
            !rules.any((r) => r.seconds == rule.seconds),
            'A warning at this time already exists.',
          );
          rules.insert(math.min(position, rules.length), rule);
          draft.defaults = draft.defaults.withWarnings(rules);
          draft.applySharedWarnings(at);
          draft.session.revision++;
        }),
      );
    }
  }
}
