import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/live/shortcuts_sheet.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

int _clickerTestsOpen = 0;

/// Whether the clicker test page is listening. While it is, Live takes no
/// key at all: a press there only shows what it would do.
bool get clickerTestOpen => _clickerTestsOpen > 0;

extension ClickerTestSettings on HomeState {
  /// Settings › Warnings & alerts › Test a clicker or pedal.
  Widget clickerTestSettings() => SettingsWide(
    main: ClickerTestView(controller: c),
    wideMain: ClickerTestView(controller: c, typicalBelow: false),
    side: (_) => SidePane(
      title: 'What a typical clicker sends',
      note: typicalClickerNote,
      children: [TypicalClickerKeys(controller: c)],
    ),
  );

  Future<void> openClickerTest() =>
      openSettingsDetail('Test a clicker or pedal', clickerTestSettings);
}

const typicalClickerNote =
    'A clicker or pedal works like a small keyboard: each button sends one key. These are the usual ones, and what each does on Live.';

/// One press on the test page.
class _Press {
  final String name, explanation;
  final bool used;
  const _Press(this.name, this.explanation, this.used);
}

/// Listens for key presses and shows, for each, the key's name and what
/// it does on Live. It swallows what it hears, so nothing reaches the
/// service, a question or a button.
class ClickerTestView extends StatefulWidget {
  final AppController controller;

  /// Whether the usual clicker keys are listed under the history, where
  /// there is no pane beside the page for them.
  final bool typicalBelow;
  const ClickerTestView({
    super.key,
    required this.controller,
    this.typicalBelow = true,
  });

  @override
  State<ClickerTestView> createState() => _ClickerTestViewState();
}

class _ClickerTestViewState extends State<ClickerTestView> {
  static const _kept = 6;
  final presses = <_Press>[];
  int count = 0;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _clickerTestsOpen++;
    // Before the focused widget hears of it, so that Space does not press
    // a button and an arrow does not move or scroll anything.
    FocusManager.instance.addEarlyKeyEventHandler(onKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(onKey);
    _clickerTestsOpen--;
    super.dispose();
  }

  /// Keys that still do their ordinary job here, so the page can be left
  /// from the keyboard. They are shown like any other press.
  static final _passed = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
  };

  KeyEventResult onKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isModifierKey(key)) return KeyEventResult.ignored;
    final swallow = _passed.contains(key)
        ? KeyEventResult.ignored
        : KeyEventResult.handled;
    if (event is! KeyDownEvent) return swallow;
    final keys = HardwareKeyboard.instance;
    final control = keys.isControlPressed, shift = keys.isShiftPressed;
    final explanation = keyExplanation(
      key,
      control: control,
      shift: shift,
      desktop: c.port.isDesktop,
      clickerOn: c.state.clickerControls,
    );
    setState(() {
      count++;
      presses.insert(
        0,
        _Press(
          keyName(key, control: control, shift: shift),
          explanation,
          !explanation.startsWith('Nothing'),
        ),
      );
      if (presses.length > _kept) presses.removeLast();
    });
    return swallow;
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final last = presses.isEmpty ? null : presses.first;
    final on = c.state.clickerControls;
    return Column(
      key: const ValueKey('clicker-test'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Press each button on your clicker or pedal. This page shows the key it sends and what that key does on Live.',
          style: text.bodyLarge?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          c.liveSession.active
              ? 'A service is running. Nothing you press here reaches it.'
              : 'Nothing you press here starts or changes a service.',
          style: text.bodyMedium?.copyWith(color: colors.muted, height: 1.4),
        ),
        if (!on) ...[
          const SizedBox(height: 16),
          AppPanel(
            child: Column(
              key: const ValueKey('clicker-test-off'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 12),
                      child: Icon(
                        Icons.info_outline,
                        size: 20,
                        color: colors.warning,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        c.port.isDesktop
                            ? 'Clicker and foot pedal is switched off, so Space, B, Page Down and → do nothing on Live, from a clicker or from the keyboard. The other keyboard shortcuts still work.'
                            : 'Clicker and foot pedal is switched off, so a clicker or pedal does nothing on Live.',
                        style: text.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: OutlinedButton(
                    key: const ValueKey('clicker-test-turn-on'),
                    onPressed: c.busy
                        ? null
                        : () => c.commit((d, _) => d.clickerControls = true),
                    child: const Text('Switch it on'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('LAST PRESS', style: sectionLabelStyle(context)),
        const SizedBox(height: 10),
        AppPanel(
          child: Semantics(
            liveRegion: true,
            container: true,
            child: last == null
                ? Row(
                    key: const ValueKey('clicker-test-waiting'),
                    children: [
                      Icon(
                        Icons.keyboard_alt_outlined,
                        size: 28,
                        color: colors.muted,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Waiting for a press',
                          style: text.titleMedium?.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        last.name,
                        key: const ValueKey('clicker-test-key'),
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 8),
                            child: Icon(
                              last.used
                                  ? Icons.check_circle_outline
                                  : Icons.remove_circle_outline,
                              size: 18,
                              color: last.used ? colors.accent : colors.muted,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              last.explanation,
                              key: const ValueKey('clicker-test-explanation'),
                              style: text.titleMedium?.copyWith(height: 1.35),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count == 1 ? '1 press so far' : '$count presses so far',
                        style: text.bodySmall?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
          ),
        ),
        if (presses.length > 1) ...[
          const SizedBox(height: 20),
          Text('BEFORE THAT', style: sectionLabelStyle(context)),
          const SizedBox(height: 10),
          AppPanel(
            padding: EdgeInsets.symmetric(
              horizontal: appLayout(context).panelPadding,
              vertical: 8,
            ),
            child: Column(
              key: const ValueKey('clicker-test-history'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, press) in presses.skip(1).indexed) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: colors.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          press.name,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          press.explanation,
                          style: text.bodySmall?.copyWith(
                            color: colors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (presses.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('clicker-test-clear'),
              onPressed: () => setState(() {
                presses.clear();
                count = 0;
              }),
              child: const Text('Clear'),
            ),
          ),
        ],
        if (widget.typicalBelow) ...[
          const SizedBox(height: 24),
          Text(
            'WHAT A TYPICAL CLICKER SENDS',
            style: sectionLabelStyle(context),
          ),
          const SizedBox(height: 6),
          Text(
            typicalClickerNote,
            style: text.bodySmall?.copyWith(color: colors.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          TypicalClickerKeys(controller: c),
        ],
      ],
    );
  }
}

/// The buttons most clickers and pedals have, the key each one sends and
/// what that key does on Live here and now.
class TypicalClickerKeys extends StatelessWidget {
  final AppController controller;
  const TypicalClickerKeys({super.key, required this.controller});

  static const _buttons = [
    ('Forward', [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.arrowRight]),
    ('Back', [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.arrowLeft]),
    ('Blank screen', [LogicalKeyboardKey.keyB, LogicalKeyboardKey.period]),
    (
      'Start or stop the slides',
      [LogicalKeyboardKey.f5, LogicalKeyboardKey.escape],
    ),
  ];

  static final _caps = {
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.period: '.',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('typical-clicker-keys'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (button, keys) in _buttons)
          PaneBlock(
            heading: button,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final key in keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MergeSemantics(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                label: keyName(key),
                                child: ExcludeSemantics(
                                  child: KeyCap(_caps[key] ?? keyName(key)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                keyExplanation(
                                  key,
                                  control: false,
                                  shift: false,
                                  desktop: c.port.isDesktop,
                                  clickerOn: c.state.clickerControls,
                                ),
                                style: text.bodyMedium?.copyWith(height: 1.35),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Text(
          'A foot pedal usually sends Page Down and Page Up, or Space. Many can be set to send a different key with the maker’s own program.',
          style: text.bodySmall?.copyWith(color: colors.muted, height: 1.4),
        ),
      ],
    );
  }
}
