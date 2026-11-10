import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class BrowserPort extends FakePort {
  final opened = <String>[];
  bool browser = true;
  @override
  Future<bool> openWebPage(String url) async {
    opened.add(url);
    return browser;
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<BrowserPort> openAbout(WidgetTester t) async {
    setScreen(t, const Size(430, 1000));
    final port = BrowserPort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('About', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('About'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('about-privacy-policy')));
    await t.pumpAndSettle();
    return port;
  }

  testWidgets('Privacy policy in About opens the policy page', (t) async {
    final port = await openAbout(t);
    await t.tap(find.byKey(const ValueKey('about-privacy-policy')));
    await t.pumpAndSettle();
    expect(port.opened, [privacyPolicyUrl]);
    expect(
      privacyPolicyUrl,
      'https://immanuelokose.github.io/church-service-timer-guide/privacy-policy/',
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Without a browser, the address is shown instead', (t) async {
    final port = await openAbout(t);
    port.browser = false;
    await t.tap(find.byKey(const ValueKey('about-privacy-policy')));
    await t.pumpAndSettle();
    expect(find.textContaining(privacyPolicyUrl), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
