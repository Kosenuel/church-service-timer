import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:flutter/material.dart';

/// The shortcuts sheet: every key the app answers to, opened with ? or F1
/// on a computer, from Commands, the Live menu and Settings search.
extension ShortcutsSheet on HomeState {
  /// On a computer, with the controls unlocked and nothing else on top.
  /// Lock controls blocks the sheet like every other key.
  bool get shortcutsSheetAvailable =>
      c.ready &&
      c.port.isDesktop &&
      !controlsLocked &&
      !miniTimer &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> openShortcutsSheet() async {
    if (!shortcutsSheetAvailable) return;
    await showAppSheet<void>(
      context,
      maxWidth: 920,
      builder: (_) => const ShortcutsSheetView(),
    );
  }
}

/// A key as a key cap: the quiet lettering of [KeyHint] in a small
/// outlined box.
class KeyCap extends StatelessWidget {
  final String text;
  const KeyCap(this.text, {super.key});

  static const _arrows = {'→': Icons.arrow_forward, '←': Icons.arrow_back};
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final ink = colors.text.withValues(alpha: .86);
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.input,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          top: BorderSide(color: colors.border),
          left: BorderSide(color: colors.border),
          right: BorderSide(color: colors.border),
          bottom: BorderSide(color: colors.border, width: 2),
        ),
      ),
      // An arrow key is drawn, so it does not depend on the font.
      child: _arrows.containsKey(text)
          ? Icon(_arrows[text], size: 15, color: ink)
          : Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w500,
                letterSpacing: .4,
                color: ink,
              ),
            ),
    );
  }
}

/// The ways to press one shortcut, as key caps: "Space or B", "Ctrl Z".
class KeyCaps extends StatelessWidget {
  final List<List<String>> caps;
  final String joiner;
  const KeyCaps(this.caps, {super.key, this.joiner = 'or'});

  /// The same in words, for a screen reader.
  String get spoken => caps.map((keys) => keys.join(' ')).join(' $joiner ');

  @override
  Widget build(BuildContext context) {
    final quiet = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: appColors(context).muted);
    return ExcludeSemantics(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, keys) in caps.indexed) ...[
            if (i > 0) Text(joiner, style: quiet),
            for (final key in keys) KeyCap(key),
          ],
        ],
      ),
    );
  }
}

/// The sheet's content: two rules, then the keys in three plain groups.
class ShortcutsSheetView extends StatelessWidget {
  const ShortcutsSheetView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;

    Widget rule(IconData icon, String words) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10),
            child: Icon(icon, size: 18, color: colors.accent),
          ),
          Expanded(
            child: Text(words, style: text.bodyMedium?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );

    Widget row(Shortcut s, bool stacked) {
      final caps = KeyCaps(s.caps, joiner: s.joiner);
      final words = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.action,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            '${s.confirm[0].toUpperCase()}${s.confirm.substring(1)}',
            style: text.bodySmall?.copyWith(color: colors.muted, height: 1.3),
          ),
        ],
      );
      return Tooltip(
        message: s.when,
        waitDuration: const Duration(milliseconds: 600),
        child: Semantics(
          key: ValueKey('shortcut-${s.id}'),
          container: true,
          label: '${caps.spoken}: ${s.action}, ${s.confirm}. ${s.when}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      caps,
                      const SizedBox(height: 6),
                      ExcludeSemantics(child: words),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 148, child: caps),
                      const SizedBox(width: 12),
                      Expanded(child: ExcludeSemantics(child: words)),
                    ],
                  ),
          ),
        ),
      );
    }

    Widget group(ShortcutGroup g) => LayoutBuilder(
      builder: (context, space) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneLabel(g.title),
          const SizedBox(height: 4),
          Text(
            g.when,
            style: text.bodySmall?.copyWith(color: colors.muted, height: 1.35),
          ),
          const SizedBox(height: 6),
          for (final s in shortcuts.where((s) => s.group == g))
            row(s, space.maxWidth < 330),
          const SizedBox(height: 18),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, space) {
        final twoColumns = space.maxWidth >= 720;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            key: const ValueKey('shortcuts-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Text('Keyboard shortcuts', style: text.titleLarge),
              ),
              const SizedBox(height: 6),
              rule(Icons.task_alt, shortcutsConfirmRule),
              rule(Icons.lock_outline, shortcutsLockRule),
              const SizedBox(height: 14),
              Divider(height: 1, thickness: 1, color: colors.border),
              Flexible(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.only(top: 18),
                  child: twoColumns
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: group(ShortcutGroup.service)),
                            const SizedBox(width: 36),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  group(ShortcutGroup.stage),
                                  group(ShortcutGroup.moving),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final g in ShortcutGroup.values) group(g),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
