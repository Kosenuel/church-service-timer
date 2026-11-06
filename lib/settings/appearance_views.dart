import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';

class AppearanceControls extends StatelessWidget {
  final AppearancePreferences value;
  final ValueChanged<AppearancePreferences>? onChanged;
  const AppearanceControls({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChoiceField<String>(
        key: const ValueKey('layout-density'),
        value: value.density,
        decoration: const InputDecoration(labelText: 'Layout density'),
        options: [
          for (final id in ['compact', 'comfortable', 'spacious', 'automatic'])
            ChoiceOption(value: id, label: densityName(id)),
        ],
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(value.copyWith(density: v)),
      ),
      const SizedBox(height: 8),
      Text(
        value.density == 'automatic'
            ? 'Adapts to the available window. Using ${densityName(appLayout(context).density)} here.'
            : 'Changes spacing and control size. Text follows your phone’s text-size setting.',
      ),
      const SizedBox(height: 16),
      ChoiceField<String>(
        key: const ValueKey('divider-style'),
        value: value.dividers,
        decoration: const InputDecoration(labelText: 'Divider style'),
        options: const [
          ChoiceOption(value: 'subtle', label: 'Subtle'),
          ChoiceOption(value: 'strong', label: 'Strong'),
          ChoiceOption(value: 'hidden', label: 'Hidden'),
        ],
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(value.copyWith(dividers: v)),
      ),
      const SizedBox(height: 16),
      ChoiceField<String>(
        key: const ValueKey('picker-feedback'),
        value: value.pickerFeedback,
        decoration: const InputDecoration(labelText: 'Picker feedback'),
        options: const [
          ChoiceOption(value: 'off', label: 'Off'),
          ChoiceOption(value: 'haptics', label: 'Haptics only'),
          ChoiceOption(value: 'sound', label: 'Sound only'),
          ChoiceOption(value: 'both', label: 'Sound + haptics'),
        ],
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(value.copyWith(pickerFeedback: v)),
      ),
      const SizedBox(height: 8),
      const Text(
        'Discreet feedback while adjusting time wheels. Respects system sound and touch-feedback settings.',
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('High contrast'),
        subtitle: const Text(
          'Stronger text, outlines and selection highlights.',
        ),
        value: value.highContrast,
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(value.copyWith(highContrast: v)),
      ),
      const AppDivider(indent: 0, endIndent: 0),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reduced motion'),
        subtitle: const Text(
          'Quieter navigation and interface effects. Stage cue effects and the clock colon keep their own settings.',
        ),
        value: value.reducedMotion,
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(value.copyWith(reducedMotion: v)),
      ),
      Text(
        'These preferences stay on this device. Your phone’s accessibility settings are also respected.',
        style: TextStyle(color: appColors(context).muted),
      ),
    ],
  );
}

/// Non-interactive examples use the same tokens as real list rows and menus.
class AppearanceSample extends StatelessWidget {
  /// Compact: program row, divider, action and delete only, for the pinned
  /// preview above the Appearance tabs.
  final bool compact;
  const AppearanceSample({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context), layout = appLayout(context);
    return Semantics(
      label: 'Layout preview: sample program, active segment and action menu',
      child: Card(
        key: const ValueKey('appearance-sample'),
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, compact ? 14 : 16, 16, 8),
              child: Text(
                'PREVIEW · ${densityName(layout.density).toUpperCase()}',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: compact ? 11 : 12,
                  letterSpacing: compact ? 1 : null,
                  fontWeight: compact ? FontWeight.w400 : FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: layout.rowInsets,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Youth sunday',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '4 segments · 55 min',
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            if (!compact) ...[
              const AppDivider(),
              ListTile(
                selected: true,
                leading: Icon(Icons.play_arrow, color: colors.accent),
                title: const Text(
                  'Praise & Worship',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('15 min · Now'),
              ),
            ],
            const AppDivider(),
            const ListTile(
              leading: Icon(Icons.ios_share),
              title: Text('Export program'),
            ),
            const AppDivider(essential: true),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.error),
              title: Text(
                'Delete program',
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact preview pinned above the Appearance tabs; follows the previewed
/// theme because the whole app re-themes while previewing.
class ThemePreviewCard extends StatelessWidget {
  final String name;
  const ThemePreviewCard({super.key, required this.name});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    Widget action(String text, {bool filled = false}) => Expanded(
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? colors.accent : null,
          border: filled ? null : Border.all(color: colors.accent, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: filled ? colors.background : colors.accent,
          ),
        ),
      ),
    );
    return Semantics(
      label: 'Preview of the selected theme',
      child: Container(
        key: const ValueKey('theme-preview'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PREVIEW · ${name.toUpperCase()}',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Praise & Worship',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '15 min · Now',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    '13:30',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w300,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  action('Pause', filled: true),
                  const SizedBox(width: 8),
                  action('Next segment'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
