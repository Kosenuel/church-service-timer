import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/live/service_dial.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/waiting.dart';
import '../support/widget_setup.dart';
import 'desktop_layout_test.dart' show DesktopFakePort, sunday;

// The finishing touches that bring the desktop layouts up to their
// mockups: cues set in the stage's own face, the Dial's "Up next" and
// clickable ring, screens and activity in a tall window, the Keys status
// line, and the rows that list paired and web screens.

void main() {
  setUpAll(loadAppFonts);
  // The device rows talk to a real local web server.
  setUpAll(() => HttpOverrides.global = null);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  /// The Sunday service part-way through its third segment, as in the
  /// desktop layout tests; [advances] moves on through more segments.
  Future<AppController> running(
    WidgetTester t, {
    Size size = const Size(1366, 768),
    String layout = 'three_panes',
    FakePort? on,
    int advances = 2,
    bool pump = true,
  }) async {
    setScreen(t, size);
    final port = on ?? DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: layout),
    );
    await c.act('load', value: sunday());
    await c.act('start');
    var at = 0;
    for (final seconds in const [340, 1330, 2400, 600].take(advances)) {
      at += seconds;
      port.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    port.at = after(at + 1642);
    await c.tick();
    if (pump) {
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
    }
    return c;
  }

  Finder cueButton(String text) => find.ancestor(
    of: find.text(text),
    matching: find.bySubtype<OutlinedButton>(),
  );
  Finder inside(Finder parent, Finder child) =>
      find.descendant(of: parent, matching: child);

  group('cue buttons', () {
    testWidgets('a desktop layout sets each cue in the stage text face', (
      t,
    ) async {
      for (final layout in ['three_panes', 'mission_control', 'dial', 'keys']) {
        final c = await running(t, layout: layout);
        final cue = c.state.stageCues.first.text;
        final label = t.widget<Text>(find.text(cue));
        expect(label.style?.fontFamily, 'Tinos', reason: layout);
        expect(label.style?.fontWeight, FontWeight.w700, reason: layout);
        // Larger than the 14 px button label it replaces.
        expect(label.style!.fontSize, greaterThan(14), reason: layout);
        expect(label.maxLines, 2, reason: layout);
        final button = cueButton(cue);
        expect(
          inside(button, find.byIcon(Icons.chat_bubble_outline)),
          findsNothing,
          reason: layout,
        );
        // The number key, the tooltip and the button itself are as before.
        expect(inside(button, find.text('1')), findsOneWidget, reason: layout);
        expect(find.byTooltip(cue), findsOneWidget, reason: layout);
        expect(
          t.widget<OutlinedButton>(button).onPressed,
          isNotNull,
          reason: layout,
        );
        await t.tap(button);
        await t.pumpAndSettle();
        expect(c.state.session.alert?.text, cue, reason: layout);
        expect(t.takeException(), isNull, reason: layout);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a cue that cannot be sent is disabled and says why', (
      t,
    ) async {
      final c = await running(t);
      final cue = c.state.stageCues.first.text;
      await t.tap(find.byKey(const ValueKey('control-lock')));
      await t.pumpAndSettle();
      expect(t.widget<OutlinedButton>(cueButton(cue)).onPressed, isNull);
      final reason = t
          .widget<UnavailableAction>(
            find.ancestor(
              of: find.text(cue),
              matching: find.byType(UnavailableAction),
            ),
          )
          .reason;
      expect(reason, isNotNull);
      expect(reason, isNotEmpty);
      expect(t.widget<Text>(find.text(cue)).style?.fontFamily, 'Tinos');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Classic and the phone keep the icon and the app font', (
      t,
    ) async {
      Future<void> unchanged(AppController c, String reason) async {
        final cue = c.state.stageCues.first.text;
        final label = t.widget<Text>(find.text(cue));
        expect(label.style, isNull, reason: reason);
        expect(
          inside(cueButton(cue), find.byIcon(Icons.chat_bubble_outline)),
          findsOneWidget,
          reason: reason,
        );
        await t.pumpWidget(const SizedBox());
      }

      await unchanged(await running(t, layout: 'classic'), 'Classic');
      desktopWording = false;
      await unchanged(
        await running(t, size: const Size(430, 1000), on: FakePort()),
        'phone',
      );
      // A desktop layout in a window too small for it.
      await unchanged(
        await running(t, size: const Size(1100, 800)),
        'small window',
      );
    });
  });

  group('the service ring', () {
    // Welcome 5, Praise & Worship 20, Sermon 40, Response 10, Closing 5.
    const minute = 60000;
    const pieces = [
      TimelinePiece(0, 0, 5 * minute, 5 * minute),
      TimelinePiece(1, 5 * minute, 20 * minute, 20 * minute),
      TimelinePiece(2, 25 * minute, 40 * minute, 40 * minute),
      TimelinePiece(3, 65 * minute, 10 * minute, 10 * minute),
      TimelinePiece(4, 75 * minute, 5 * minute, 5 * minute),
    ];
    const total = 80 * minute, size = 400.0;
    const g = DialGeometry(size);
    Offset at(double angle, double radius) =>
        g.centre + Offset(math.cos(angle), math.sin(angle)) * radius;
    Offset middleOf(TimelinePiece p, [double? radius]) => at(
      DialGeometry.angle(p.startMs + p.lengthMs ~/ 2, total),
      radius ?? g.outer,
    );

    test('a position on the ring is the segment drawn there', () {
      for (final p in pieces) {
        expect(dialSegmentAt(middleOf(p), size, pieces, total), p.index);
        // Either edge of the ring, and the number just outside it.
        for (final radius in [
          g.outer - g.stroke / 2,
          g.outer + g.stroke / 2,
          g.outer + g.stroke / 2 + 13,
        ]) {
          expect(
            dialSegmentAt(middleOf(p, radius), size, pieces, total),
            p.index,
            reason: 'segment ${p.index + 1} at radius $radius',
          );
        }
      }
      // The ring starts at three o'clock and runs clockwise.
      expect(dialSegmentAt(at(.01, g.outer), size, pieces, total), 0);
      expect(
        dialSegmentAt(at(math.pi * 1.5 - .01, g.outer), size, pieces, total),
        4,
      );
      // Where one segment meets the next.
      final join = DialGeometry.angle(5 * minute, total);
      expect(dialSegmentAt(at(join - .01, g.outer), size, pieces, total), 0);
      expect(dialSegmentAt(at(join + .01, g.outer), size, pieces, total), 1);
    });

    test('the gap by the cross, the centre and outside are no segment', () {
      expect(dialSegmentAt(g.cross, size, pieces, total), isNull);
      for (final angle in [-.02, -math.pi / 4, -math.pi / 2 + .02]) {
        expect(
          dialSegmentAt(at(angle, g.outer), size, pieces, total),
          isNull,
          reason: 'angle $angle',
        );
      }
      expect(dialSegmentAt(g.centre, size, pieces, total), isNull);
      // The inner ring belongs to the running segment's countdown.
      expect(
        dialSegmentAt(middleOf(pieces[2], g.inner), size, pieces, total),
        isNull,
      );
      expect(
        dialSegmentAt(middleOf(pieces[2], g.outer + 60), size, pieces, total),
        isNull,
      );
      expect(dialSegmentAt(const Offset(-5, -5), size, pieces, total), isNull);
      expect(dialSegmentAt(middleOf(pieces[0]), size, const [], 1), isNull);
    });

    test('a skipped segment has no piece to click', () {
      final kept = [pieces[0], pieces[2]];
      expect(dialSegmentAt(middleOf(pieces[1]), size, kept, total), isNull);
    });

    testWidgets('clicking a piece opens that segment; the middle does not', (
      t,
    ) async {
      final c = await running(t, layout: 'dial');
      final dial = find.byKey(const ValueKey('service-dial'));
      final origin = t.getTopLeft(dial);
      final live = DialGeometry(t.getSize(dial).width);
      final drawn = timelinePieces(c.liveSession, c.now);
      final whole = drawn.last.startMs + drawn.last.lengthMs;
      Offset on(int index) {
        final p = drawn[index];
        final angle = DialGeometry.angle(p.startMs + p.lengthMs ~/ 2, whole);
        return origin +
            live.centre +
            Offset(math.cos(angle), math.sin(angle)) * live.outer;
      }

      // The middle, and the gap by the cross, open nothing.
      await t.tapAt(origin + live.centre);
      await t.tapAt(origin + live.cross);
      await t.pumpAndSettle();
      expect(find.text('Segment details'), findsNothing);

      for (final (index, line) in const [
        (1, 'Segment 2 of 5 · 20 min planned'),
        (4, 'Segment 5 of 5 · 5 min planned'),
      ]) {
        await t.tapAt(on(index));
        await t.pumpAndSettle();
        expect(find.text('Segment details'), findsOneWidget);
        expect(find.text(line), findsOneWidget);
        await t.tap(find.text('Close'));
        await t.pumpAndSettle();
      }

      // A mouse shows the hand over the ring only.
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: origin + live.centre);
      addTearDown(mouse.removePointer);
      MouseCursor cursor() =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
      await t.pump();
      expect(cursor(), SystemMouseCursors.basic);
      await mouse.moveTo(on(3));
      await t.pump();
      await t.pump();
      expect(cursor(), SystemMouseCursors.click);
      await mouse.moveTo(origin + live.centre);
      await t.pump();
      await t.pump();
      expect(cursor(), SystemMouseCursors.basic);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Up next', () {
    final block = find.byKey(const ValueKey('up-next'));

    testWidgets('The dial names what follows, above the rundown', (t) async {
      await running(t, layout: 'dial');
      expect(
        inside(find.byKey(const ValueKey('rundown-pane')), block),
        findsOneWidget,
      );
      expect(inside(block, find.text('Up next')), findsOneWidget);
      expect(inside(block, find.text('Response')), findsOneWidget);
      expect(
        inside(
          block,
          find.textContaining(
            RegExp(r'^10 min · Worship team · starts about \d\d:\d\d$'),
          ),
        ),
        findsOneWidget,
      );
      // Above the list, and the list still shows every segment.
      expect(
        t.getRect(block).bottom,
        lessThanOrEqualTo(
          t.getRect(find.byKey(const ValueKey('rundown-0'))).top,
        ),
      );
      expect(
        find.byKey(const ValueKey('rundown-4')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the last segment says so', (t) async {
      await running(t, layout: 'dial', advances: 4);
      expect(inside(block, find.text('Final segment')), findsOneWidget);
      expect(inside(block, find.textContaining('starts about')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Three panes, and a service not yet started, have none', (
      t,
    ) async {
      await running(t);
      expect(block, findsNothing);
      await t.pumpWidget(const SizedBox());

      setScreen(t, const Size(1366, 768));
      final c = AppController(DesktopFakePort());
      await c.initialize(startTicker: false);
      await c.commit(
        (draft, _) =>
            draft.appearance = draft.appearance.copyWith(desktopLayout: 'dial'),
      );
      await c.act('load', value: sunday());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('rundown-pane')), findsOneWidget);
      expect(block, findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('screens and activity beside the panes', () {
    final screens = find.byKey(const ValueKey('screens-section'));
    final activity = find.byKey(const ValueKey('activity-section'));

    testWidgets('a full HD window has both under the cues', (t) async {
      for (final layout in ['three_panes', 'dial']) {
        await running(t, layout: layout, size: const Size(1920, 1080));
        final pane = find.byKey(const ValueKey('live-stage-pane'));
        expect(inside(pane, screens), findsOneWidget, reason: layout);
        expect(inside(pane, activity), findsOneWidget, reason: layout);
        expect(
          inside(screens, find.text('Showing on Simulator')),
          findsOneWidget,
          reason: layout,
        );
        expect(
          inside(activity, find.text('Sermon started')),
          findsOneWidget,
          reason: layout,
        );
        // Under the cues, and in view without scrolling.
        final blank = t.getRect(find.text('Blank screen'));
        expect(t.getRect(screens).top, greaterThan(blank.bottom));
        expect(t.getRect(activity).top, greaterThan(t.getRect(screens).top));
        expect(t.getRect(screens).bottom, lessThanOrEqualTo(1080));
        expect(
          inside(activity, find.text('Activity')).hitTestable(),
          findsOneWidget,
          reason: layout,
        );
        expect(find.text('Blank screen').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull, reason: layout);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a laptop window keeps to the preview and the cues', (t) async {
      for (final layout in ['three_panes', 'dial']) {
        await running(t, layout: layout);
        expect(screens, findsNothing, reason: layout);
        expect(activity, findsNothing, reason: layout);
        expect(find.text('Blank screen').hitTestable(), findsOneWidget);
        expect(
          t.getRect(find.text('Quick timer')).bottom,
          lessThanOrEqualTo(768),
          reason: layout,
        );
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  group('the Keys status line', () {
    final legend = find.byKey(const ValueKey('key-legend'));
    final status = find.byKey(const ValueKey('live-status-line'));
    const reminder = 'Every action asks to confirm';

    testWidgets('says where the output is going, beside the keys', (t) async {
      await running(t, layout: 'keys');
      expect(inside(legend, status), findsOneWidget);
      expect(
        inside(status, find.text('Simulator · no physical display')),
        findsOneWidget,
      );
      // On the same line as the keys, left of the reminder.
      expect(
        inside(legend, find.textContaining('Next segment')),
        findsOneWidget,
      );
      final line = t.getRect(status), words = t.getRect(find.text(reminder));
      expect(line.right, lessThan(words.left));
      expect(words.right, lessThanOrEqualTo(1366));
      expect(t.getRect(legend).bottom, lessThanOrEqualTo(768));
      expect(t.getSize(legend).height, 28);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('says when the controls are locked', (t) async {
      await running(t, layout: 'keys');
      expect(find.textContaining('Controls locked'), findsNothing);
      await t.tap(find.byKey(const ValueKey('control-lock')));
      await t.pumpAndSettle();
      expect(
        inside(
          status,
          find.text('Simulator · no physical display   ·   Controls locked'),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.longPress(find.byKey(const ValueKey('unlock-controls')));
      await t.pumpAndSettle();
      expect(find.textContaining('Controls locked'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('stays on its own when key labels are off', (t) async {
      final c = await running(t, layout: 'keys');
      await c.commit(
        (draft, _) =>
            draft.appearance = draft.appearance.copyWith(keyHints: 'off'),
      );
      await t.pumpAndSettle();
      expect(inside(legend, find.textContaining('Next segment')), findsNothing);
      expect(find.text(reminder), findsNothing);
      expect(
        inside(status, find.text('Simulator · no physical display')),
        findsOneWidget,
      );
      expect(t.getRect(status).left, lessThan(60));
      expect(t.getRect(legend).bottom, lessThanOrEqualTo(768));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a long sign name is cut short, not pushed off the line', (
      t,
    ) async {
      const sign =
          'Main auditorium front of house LED sign above the choir stalls '
          'on the left hand side by the organ loft';
      final c = await running(t, layout: 'keys', pump: false);
      c.hardware.rememberedName = sign;
      expect(await c.selectDestination('led'), isTrue);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('control-lock')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final text = t.widget<Text>(
        inside(status, find.textContaining('$sign · ')),
      );
      expect(text.data, endsWith('Controls locked'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      // It takes the reminder's place, and keeps inside the window.
      expect(find.text(reminder), findsNothing);
      expect(inside(legend, find.textContaining('Cues')), findsOneWidget);
      expect(t.getRect(status).right, lessThanOrEqualTo(1366 - 20));
      expect(
        t.getRect(status).left,
        greaterThan(
          t.getRect(inside(legend, find.textContaining('Cues'))).right,
        ),
      );
      expect(t.getSize(legend).height, 28);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('the screens section lists devices', () {
    testWidgets(
      'paired screens, an operator and a web screen, each with its state',
      (t) async {
        late AppController c;
        final hubs = <String, PairHub>{};
        final client = HttpClient();
        await t.runAsync(() async {
          c = await running(
            t,
            layout: 'keys',
            // Tall enough for the section under the two notices at the top.
            size: const Size(1920, 1300),
            pump: false,
          );
          await c.pairing.host('127.0.0.1');
          for (final (name, role) in const [
            ('Stage left TV', 'stage'),
            ('Balcony screen', 'stage'),
            ('Foyer TV', 'stage'),
            ('Sound desk', 'operator'),
          ]) {
            final hub = hubs[name] = PairHub();
            await hub.join(c.pairing.code!.encode(), name, role);
            await until(() => c.pairing.peers.any((p) => p.name == name));
            await c.pairing.approve(
              c.pairing.peers.firstWhere((p) => p.name == name),
            );
            await until(() => !hub.stale);
          }
          String id(String name) =>
              c.pairing.savedDevices.firstWhere((d) => d.name == name).id;
          // The balcony screen loses its Wi-Fi without saying goodbye.
          await hubs['Balcony screen']!.stop(preserveClient: true);
          await until(() => !c.pairing.connectedDevice(id('Balcony screen')));
          // The foyer screen is disconnected from Screens & devices.
          await c.pairing.disconnectDevice(id('Foyer TV'));
          // A smart TV opens the stage display in its browser.
          await eventually(() => c.webStage.running);
          final request = await client.postUrl(
            Uri.parse('${c.webStageUrl}/api/join'),
          );
          request.headers.set(
            'user-agent',
            'Mozilla/5.0 (SMART-TV; Linux; Tizen 7.0) Chrome/120.0 Safari/537',
          );
          request.write(
            jsonEncode({'code': c.webStage.teamCode, 'role': 'stage'}),
          );
          await (await request.close()).drain<void>();
          await until(() => c.webStage.activeDevices.isNotEmpty);
        });
        await t.pumpWidget(TimerApp(controller: c));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);

        final section = find.byKey(const ValueKey('screens-section'));
        final words = t
            .widgetList<Text>(inside(section, find.byType(Text)))
            .map((w) => w.data)
            .toList();
        expect(words, [
          'Screens & sign',
          'Manage',
          'Showing on Simulator',
          'no physical display',
          'Stage left TV',
          'Stage screen · connected',
          'Balcony screen',
          'Stage screen · not answering',
          'Foyer TV',
          'Stage screen · disconnected',
          'Sound desk',
          'Operator · connected',
          'TV · Chrome',
          'Web · stage display',
        ]);
        // Only screens that are showing now count on the status line.
        expect(
          inside(
            find.byKey(const ValueKey('live-status-line')),
            find.text('Simulator · no physical display   ·   2 stage screens'),
          ),
          findsOneWidget,
        );

        // Handing the service to the operator shows in their row.
        await t.runAsync(() async {
          c.pairing.grant(
            c.pairing.peers.firstWhere((p) => p.name == 'Sound desk'),
          );
          await until(() => c.pairing.owner.isNotEmpty);
        });
        await t.pumpAndSettle();
        expect(
          inside(section, find.text('Operator · controls the service')),
          findsOneWidget,
        );

        await t.runAsync(() async {
          client.close(force: true);
          for (final hub in hubs.values) {
            await hub.stop();
          }
          await c.pairing.stop();
        });
        await t.pumpAndSettle();
        // Nothing is shared any more, so nothing is listed as missing.
        expect(
          inside(section, find.text('No stage screens have joined.')),
          findsOneWidget,
        );
        expect(find.textContaining('not answering'), findsNothing);
        await t.pumpWidget(const SizedBox());
        for (final hub in hubs.values) {
          hub.dispose();
        }
      },
    );

    testWidgets('people following the order of service are counted', (t) async {
      late AppController c;
      final client = HttpClient();
      await t.runAsync(() async {
        c = await running(
          t,
          layout: 'mission_control',
          size: const Size(1920, 1080),
          pump: false,
        );
        await c.pairing.host('127.0.0.1');
        await eventually(() => c.webStage.running);
        for (var i = 0; i < 2; i++) {
          final request = await client.postUrl(
            Uri.parse('${c.webStageUrl}/api/join'),
          );
          request.write(jsonEncode({'code': c.webStageSettings.orderCode}));
          await (await request.close()).drain<void>();
        }
        await until(() => c.webStage.activeDevices.length == 2);
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final section = find.byKey(const ValueKey('screens-section'));
      expect(
        inside(section, find.text('Order of service on the web')),
        findsOneWidget,
      );
      expect(inside(section, find.text('2 following')), findsOneWidget);
      expect(inside(section, find.textContaining('Web ·')), findsNothing);
      expect(
        inside(section, find.text('No stage screens have joined.')),
        findsNothing,
      );
      await t.runAsync(() async {
        client.close(force: true);
        await c.pairing.stop();
      });
      await t.pumpWidget(const SizedBox());
    });
  });
}
