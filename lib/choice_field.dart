import 'package:flutter/material.dart';
import 'app_theme.dart';

class ChoiceOption<T> {
  final T value;
  final String label;
  const ChoiceOption({required this.value, required this.label});
}

/// Controlled, themed selection: short choices stay visible; longer lists open
/// a cancellable sheet. The current value never changes merely by opening it.
class ChoiceField<T> extends StatelessWidget {
  final T? value;
  final InputDecoration decoration;
  final List<ChoiceOption<T>> options;
  final ValueChanged<T?>? onChanged;
  const ChoiceField({
    super.key,
    this.value,
    required this.decoration,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final title = decoration.labelText ?? 'Choose an option';
    final enabled = onChanged != null && options.isNotEmpty;
    final selected = options.where((o) => o.value == value).firstOrNull;
    final compact =
        options.length <= 3 &&
        options.every((o) => o.label.length <= 16) &&
        value != null;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.label),
                  selected: option.value == value,
                  showCheckmark: true,
                  onSelected: enabled ? (_) => onChanged!(option.value) : null,
                ),
            ],
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      value: selected?.label ?? 'Select an option',
      child: Material(
        color: colors.input,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () async {
                  final result = await showModalBottomSheet<T>(
                    context: context,
                    sheetAnimationStyle: reduceAppMotion(context)
                        ? AnimationStyle.noAnimation
                        : null,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: colors.surface,
                    showDragHandle: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(26),
                      ),
                    ),
                    builder: (_) => _ChoiceSheet<T>(
                      title: title,
                      options: options,
                      value: value,
                    ),
                  );
                  if (context.mounted && result != null)
                    onChanged?.call(result);
                }
              : null,
          child: InputDecorator(
            decoration: decoration.copyWith(
              enabled: enabled,
              suffixIcon: const Icon(Icons.expand_more_rounded),
            ),
            child: Text(
              selected?.label ?? 'Select an option',
              style: TextStyle(
                color: enabled ? colors.text : colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceSheet<T> extends StatefulWidget {
  final String title;
  final List<ChoiceOption<T>> options;
  final T? value;
  const _ChoiceSheet({required this.title, required this.options, this.value});
  @override
  State<_ChoiceSheet<T>> createState() => _ChoiceSheetState<T>();
}

class _ChoiceSheetState<T> extends State<_ChoiceSheet<T>> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final layout = appLayout(context);
    final filtered = widget.options
        .where((o) => o.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.panelPadding,
        0,
        layout.panelPadding,
        layout.gap + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close choices',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (widget.options.length > 8) ...[
              SizedBox(height: layout.gap),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search options',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching options'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const AppDivider(indent: 0, endIndent: 0),
                      itemBuilder: (context, index) {
                        final option = filtered[index],
                            selected = option.value == widget.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            selected: selected,
                            selectedTileColor: colors.accent.withValues(
                              alpha: .12,
                            ),
                            selectedColor: colors.text,
                            title: Text(
                              option.label,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check_circle, color: colors.accent)
                                : null,
                            onTap: () => Navigator.pop(context, option.value),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
