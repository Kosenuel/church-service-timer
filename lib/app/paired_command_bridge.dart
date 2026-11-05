import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';

/// Validates commands from a paired operator before they reach
/// [AppController.act]. Only the listed Live actions are accepted, prepared
/// cues must match the host's current service, segment and cue version, and
/// time adjustments are bounded.
class PairedCommandBridge {
  final AppController app;
  PairedCommandBridge(this.app);

  Future<bool> handle(String action, Object? value, int? revision) async {
    if (!{
          'pause',
          'adjust',
          'advance',
          'jump',
          'clock',
          'clearCue',
          'endScreen',
          'cue',
          'timer',
          'blank',
          'end',
        }.contains(action) ||
        app.busy) {
      app.error = app.busy
          ? 'Host is saving another action. Try again.'
          : 'This action is unavailable.';
      return false;
    }
    if (action == 'adjust' && (value is! int || value.abs() > 3600))
      return false;
    if (action == 'cue') {
      if (value is Map) {
        if (value['session'] != app.state.session.id ||
            value['segment'] != app.state.session.index) {
          app.error =
              'The service or segment changed. Review the current service.';
          return false;
        }
        final i = value['index'];
        if (i is! int ||
            i < 0 ||
            i >= app.state.stageCues.length ||
            value['version'] != jsonEncode(app.state.stageCues[i].toJson())) {
          app.error = 'This prepared cue changed. Select its updated button.';
          return false;
        }
        value = i;
        revision = app.state.session.revision;
      }
      if (value is! int || value < 0 || value >= app.state.stageCues.length)
        return false;
      value = app.state.stageCues[value];
    }
    return await app.act(
      action,
      value: value,
      revision: revision,
      remote: true,
    );
  }

  /// The status shown to the paired operator after a command.
  String message(bool ok, String action) => !ok
      ? (app.error ?? 'Action unavailable. Review the host service.')
      : action == 'cue' &&
            app.hardware.enabled &&
            (!app.hardware.connected ||
                app.hardware.held ||
                app.hardware.interrupted)
      ? 'Cue applied to the service and paired screens · LED sign unavailable or held'
      : 'Command applied';
}
