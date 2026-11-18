import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// Settings › Appearance › Layout: the desktop layout presets, the looks
/// saved under a name, and the way back to the default.
class DesktopLayoutSection extends StatelessWidget {
  final AppearancePreferences appearance;
  final String themeId;
  final List<SavedLook> looks;

  /// Whether the app is on a computer, where key labels show by default.
  final bool desktop;

  /// A new layout or look, with the theme that goes with it. Null while
  /// saving.
  final void Function(AppearancePreferences appearance, String themeId)?
  onChanged;
  final VoidCallback? onSaveLook, onReset;
  final ValueChanged<SavedLook>? onDeleteLook;
  const DesktopLayoutSection({
    super.key,
    required this.appearance,
    required this.themeId,
    required this.looks,
    required this.desktop,
    required this.onChanged,
    required this.onSaveLook,
    required this.onReset,
    required this.onDeleteLook,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final chosen = effectiveDesktopLayout(appearance.desktopLayout);
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    final keysOn = switch (appearance.keyHints) {
      'on' => true,
      'off' => false,
      _ => desktop,
    };
    Widget heading(String text) => Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
    return Column(
      key: const ValueKey('desktop-layout-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Desktop layout'),
        const SizedBox(height: 4),
        Text(
          'How Live is arranged in a wide window, on a computer or a large tablet held sideways. Narrower windows keep the phone layout. Choosing a layout also sets its theme; change the theme afterwards if you like.',
          style: muted,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, space) {
            final columns = space.maxWidth >= 480 ? 2 : 1;
            final width = (space.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final id in builtDesktopLayouts)
                  SizedBox(
                    width: width,
                    child: _LayoutChoice(
                      id: id,
                      selected: id == chosen,
                      onTap: onChanged == null
                          ? null
                          : () => onChanged!(
                              appearance.copyWith(desktopLayout: id),
                              desktopLayoutTheme(id) ?? themeId,
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('key-hints'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show keyboard keys on buttons'),
          subtitle: const Text(
            'Space, Page Down and the other keys that work on Live.',
          ),
          value: keysOn,
          onChanged: onChanged == null
              ? null
              : (v) => onChanged!(
                  appearance.copyWith(keyHints: v ? 'on' : 'off'),
                  themeId,
                ),
        ),
        const SizedBox(height: 8),
        heading('Saved looks'),
        const SizedBox(height: 4),
        Text(
          looks.isEmpty
              ? 'Save this layout and theme together under a name, to come back to later. Saved looks are included in backups.'
              : 'Tap a look to use it. Up to $savedLookLimit; they are included in backups.',
          style: muted,
        ),
        for (final look in looks)
          ListTile(
            key: ValueKey('saved-look-${look.name}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bookmark_outline, color: colors.accent),
            title: Text(
              look.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${desktopLayoutName(effectiveDesktopLayout(look.layout))} · ${paletteFor(look.themeId).name}',
            ),
            onTap: onChanged == null
                ? null
                : () => onChanged!(look.applyTo(appearance), look.themeId),
            trailing: IconButton(
              tooltip: 'Delete ${look.name}',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDeleteLook == null
                  ? null
                  : () => onDeleteLook!(look),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('save-look'),
              onPressed: onSaveLook,
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              label: const Text('Save this look'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('reset-look'),
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 20),
              label: const Text('Reset to default'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LayoutChoice extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback? onTap;
  const _LayoutChoice({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final theme = desktopLayoutTheme(id);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        key: ValueKey('desktop-layout-$id'),
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? colors.accent : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 7,
                  child: CustomPaint(
                    painter: LayoutSketchPainter(
                      id,
                      line: colors.border,
                      fill: colors.track,
                      accent: colors.accent,
                      ground: colors.background,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        desktopLayoutName(id),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, size: 18, color: colors.accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  desktopLayoutDescription(id),
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  theme == null
                      ? 'Keeps your current theme'
                      : 'Comes with ${paletteFor(theme).name}',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small drawing of where a layout puts the rundown, timer and stage.
class LayoutSketchPainter extends CustomPainter {
  final String id;
  final Color line, fill, accent, ground;
  const LayoutSketchPainter(
    this.id, {
    required this.line,
    required this.fill,
    required this.accent,
    required this.ground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(frame, Paint()..color = ground)
      ..drawRRect(
        frame,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke,
      )
      ..save()
      ..clipRRect(frame);
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1;
    final block = Paint()..color = fill;
    final bright = Paint()..color = accent;
    void bar(double x, double y, double width, [Paint? paint]) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, width, h * .06),
            const Radius.circular(2),
          ),
          paint ?? block,
        );
    void dial(Offset centre, double radius) => canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      2.36,
      4.71,
      false,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * .22,
    );
    // The header every layout shares.
    canvas.drawLine(Offset(0, h * .14), Offset(w, h * .14), stroke);
    if (id == 'three_panes') {
      canvas
        ..drawLine(Offset(w * .26, h * .14), Offset(w * .26, h), stroke)
        ..drawLine(Offset(w * .72, h * .14), Offset(w * .72, h), stroke);
      for (var i = 0; i < 5; i++) {
        bar(w * .04, h * (.24 + i * .14), w * .18, i == 2 ? bright : null);
      }
      dial(Offset(w * .49, h * .5), h * .2);
      bar(w * .39, h * .82, w * .09, bright);
      bar(w * .5, h * .82, w * .09);
      canvas.drawRect(Rect.fromLTWH(w * .76, h * .22, w * .2, h * .24), block);
      for (var i = 0; i < 2; i++) {
        bar(w * .76, h * (.56 + i * .14), w * .09);
        bar(w * .87, h * (.56 + i * .14), w * .09);
      }
    } else {
      // Classic: a rail, then two columns of cards.
      canvas.drawLine(Offset(w * .08, h * .14), Offset(w * .08, h), stroke);
      final card = Paint()
        ..color = line
        ..style = PaintingStyle.stroke;
      void outline(Rect r) => canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        card,
      );
      outline(Rect.fromLTWH(w * .14, h * .24, w * .37, h * .68));
      outline(Rect.fromLTWH(w * .55, h * .24, w * .37, h * .3));
      outline(Rect.fromLTWH(w * .55, h * .6, w * .37, h * .5));
      dial(Offset(w * .325, h * .5), h * .16);
      bar(w * .2, h * .78, w * .12, bright);
      bar(w * .33, h * .78, w * .12);
      canvas.drawRect(Rect.fromLTWH(w * .59, h * .3, w * .29, h * .18), block);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LayoutSketchPainter old) =>
      old.id != id ||
      old.line != line ||
      old.fill != fill ||
      old.accent != accent ||
      old.ground != ground;
}

/// Asks for the name to save a look under; null when cancelled.
Future<String?> askLookName(
  BuildContext context, {
  required List<SavedLook> existing,
}) => showDialog<String>(
  context: context,
  animationStyle: reduceAppMotion(context) ? AnimationStyle.noAnimation : null,
  builder: (_) => _LookNameDialog(existing: existing),
);

class _LookNameDialog extends StatefulWidget {
  final List<SavedLook> existing;
  const _LookNameDialog({required this.existing});
  @override
  State<_LookNameDialog> createState() => _LookNameDialogState();
}

class _LookNameDialogState extends State<_LookNameDialog> {
  final name = TextEditingController();
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  bool get replaces => widget.existing.any(
    (l) => l.name.toLowerCase() == name.text.trim().toLowerCase(),
  );

  void submit() {
    try {
      final value = savedLookName(name.text);
      if (!replaces && widget.existing.length >= savedLookLimit) {
        setState(
          () => error =
              'You have $savedLookLimit saved looks. Delete one, or use the name of one to replace it.',
        );
        return;
      }
      Navigator.pop(context, value);
    } on RuleError catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save this look'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Saves the layout, theme, spacing, contrast and key labels as they are now.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('look-name'),
          controller: name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: 'Sunday morning',
            errorText: error,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) => submit(),
        ),
        if (replaces)
          const Text('This replaces the saved look with the same name.'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('look-name-save'),
        onPressed: submit,
        child: const Text('Save look'),
      ),
    ],
  );
}
