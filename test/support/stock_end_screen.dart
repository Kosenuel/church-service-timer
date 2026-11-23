import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

/// Gives the app-wide default and every saved program the stock end screen
/// ("Hallelujah"), as an install made before new installs ended on the clock
/// has. For tests that are about something else than what a new install
/// ends on.
Future<void> useStockEndScreen(AppController c) => c.commit((draft, _) {
  draft.defaults = draft.defaults.withEnd(defaultEndScreen);
  draft.templates = [
    for (final t in draft.templates)
      t.withDisplay(t.display.withEnd(defaultEndScreen)),
  ];
});

/// A new install's state, but with the stock end screen as installs made
/// before new installs ended on the clock have it.
AppState stockEndState(Stamp now) {
  final a = AppState.fresh(now);
  a.defaults = a.defaults.withEnd(defaultEndScreen);
  a.templates = [
    for (final t in a.templates)
      t.withDisplay(t.display.withEnd(defaultEndScreen)),
  ];
  return a;
}
