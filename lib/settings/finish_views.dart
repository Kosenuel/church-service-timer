import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';

/// Settings › Appearance › Finish: the material of the app's background and
/// panels, as picture tiles that each draw their own material in the
/// theme being edited, and how much of it shows.
class FinishSection extends StatelessWidget {
  final AppearancePreferences value;

  /// The theme being edited, so each tile shows its material in those colours.
  final AppPalette palette;

  /// The theme being edited: Paper & Ink comes with its own finish, which is
  /// not a choice, so its tiles give way to a note.
  final String themeId;
  final ValueChanged<AppearancePreferences>? onChanged;
  const FinishSection({
    super.key,
    required this.value,
    required this.palette,
    required this.themeId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final strength = value.finishStrength == 'full' ? 1.0 : .5;
    final plain = value.highContrast || MediaQuery.highContrastOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Finish',
          key: const ValueKey('finish-title'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'The material of the app’s panels and background. Your theme’s colours stay as they are.',
          style: TextStyle(color: colors.muted),
        ),
        const SizedBox(height: 12),
        if (paperyThemeIds.contains(themeId))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${finishName(paperyFinish)} · Paper & Ink comes with its own paper finish.',
              key: const ValueKey('finish-papery-note'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, space) {
              final columns = space.maxWidth >= 760
                  ? 4
                  : space.maxWidth >= 520
                  ? 3
                  : 2;
              final rows = <List<String>>[
                for (var i = 0; i < finishIds.length; i += columns)
                  finishIds.sublist(
                    i,
                    i + columns > finishIds.length
                        ? finishIds.length
                        : i + columns,
                  ),
              ];
              return Column(
                children: [
                  for (final row in rows) ...[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < columns; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: i < row.length
                                  ? FinishTile(
                                      id: row[i],
                                      strength: strength,
                                      palette: palette,
                                      selected: value.finish == row[i],
                                      onTap: onChanged == null
                                          ? null
                                          : () => onChanged!(
                                              value.copyWith(finish: row[i]),
                                            ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Strength',
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
              ),
            ),
            SegmentedButton<String>(
              key: const ValueKey('finish-strength'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'subtle', label: Text('Subtle')),
                ButtonSegment(value: 'full', label: Text('Full')),
              ],
              selected: {value.finishStrength},
              onSelectionChanged:
                  onChanged == null ||
                      (value.finish == 'flat' &&
                          !paperyThemeIds.contains(themeId))
                  ? null
                  : (v) => onChanged!(value.copyWith(finishStrength: v.first)),
            ),
          ],
        ),
        if (plain) ...[
          const SizedBox(height: 8),
          Text(
            'High contrast is on, so panels stay plain.',
            key: const ValueKey('finish-plain-note'),
            style: TextStyle(color: colors.muted),
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const ValueKey('finish-credits'),
            onPressed: () => showFinishTextureCredits(context),
            child: const Text('Texture credits'),
          ),
        ),
      ],
    );
  }
}

/// The credits for the finish textures, from assets/finish/credits.json.
Future<List<Map<String, dynamic>>> finishTextureCredits() async {
  final raw = await rootBundle.loadString('assets/finish/credits.json');
  return [
    for (final e in jsonDecode(raw) as List)
      Map<String, dynamic>.from(e as Map),
  ];
}

/// Where the finish textures come from: photographs from Poly Haven and a
/// few made for the app, every one CC0.
Future<void> showFinishTextureCredits(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Texture credits'),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: finishTextureCredits(),
        builder: (context, snap) {
          final credits = snap.data ?? const [];
          return ListView(
            key: const ValueKey('finish-credits-list'),
            shrinkWrap: true,
            children: [
              for (final c in credits)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c['title']}'),
                  subtitle: Text(
                    '${c['author']} · ${c['license']}\n${c['source']}',
                  ),
                  isThreeLine: true,
                ),
              const Text(
                'The photographs are from Poly Haven. Every texture is CC0: none needs credit to be shown on screen; they are listed here with thanks.',
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class FinishTile extends StatelessWidget {
  final String id;
  final double strength;
  final AppPalette palette;
  final bool selected;
  final VoidCallback? onTap;
  const FinishTile({
    super.key,
    required this.id,
    required this.strength,
    required this.palette,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${finishName(id)}. ${finishDescription(id)}',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('finish-$id'),
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
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FinishSwatch(id: id, strength: strength, palette: palette),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        finishName(id),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, size: 18, color: colors.accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  finishDescription(id),
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

/// A small panel on a piece of the finish's wall, drawn with the real
/// painters, as the app would draw them in [palette].
class FinishSwatch extends StatefulWidget {
  final String id;
  final double strength;
  final AppPalette palette;
  const FinishSwatch({
    super.key,
    required this.id,
    required this.strength,
    required this.palette,
  });
  @override
  State<FinishSwatch> createState() => _FinishSwatchState();
}

class _FinishSwatchState extends State<FinishSwatch> {
  // The swatch is a little wall of its own, so a glass pane in it shows the
  // swatch's light, not the app's.
  final _wall = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final id = widget.id, palette = widget.palette, strength = widget.strength;
    final look = FinishLook.resolve(
      // The tile shows the material even where High contrast would hide it.
      palette.highContrast ? paletteFor(palette.id) : palette,
      id,
      strength,
    );
    final flat = !look.active;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FinishWallScope(
            wallKey: _wall,
            child: Stack(
              fit: StackFit.expand,
              children: [
                flat
                    ? ColoredBox(color: palette.background)
                    : FinishPaint(
                        key: _wall,
                        look: look,
                        part: FinishPart.wall,
                      ),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: .72,
                    heightFactor: .66,
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        flat
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: palette.border),
                                ),
                              )
                            : FinishPaint(
                                look: look,
                                part: FinishPart.panel,
                                corners: BorderRadius.circular(
                                  finishRadius(id) * .6,
                                ),
                              ),
                        if (!flat && stitchedFinishes.contains(id))
                          FinishPaint(
                            look: look,
                            part: FinishPart.seam,
                            corners: BorderRadius.circular(
                              finishRadius(id) * .6,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _bar(palette.text, 6, 1),
                              const SizedBox(height: 5),
                              _bar(palette.muted, 4, .7),
                              const SizedBox(height: 8),
                              _bar(palette.accent, 8, .46, round: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(Color color, double height, double width, {bool round = false}) =>
      FractionallySizedBox(
        widthFactor: width,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(round ? 99 : 3),
          ),
        ),
      );
}
