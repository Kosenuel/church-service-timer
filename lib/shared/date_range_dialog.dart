import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';

/// What [showDateRangeDialog] returns when "All dates" is applied: the
/// caller clears its filter. Compare with [identical].
final allDates = DateTimeRange(start: DateTime(1), end: DateTime(9999));

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "3 November 2026", day first as the rest of the app writes dates.
String longDate(DateTime d, {bool year = true}) =>
    '${d.day} ${_monthNames[d.month - 1]}${year ? ' ${d.year}' : ''}';

/// "3 November to 16 November 2026"; one day is written once.
String dateRangeWords(DateTime start, DateTime end) => start == end
    ? longDate(start)
    : '${longDate(start, year: start.year != end.year)} to ${longDate(end)}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);
DateTime _addMonths(DateTime month, int months) =>
    DateTime(month.year, month.month + months);
int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// The ready-made ranges beside the calendar, for [today], kept inside
/// [first] and [last]. A range wholly outside them is left out.
List<(String, DateTimeRange)> dateRangeShortcuts(
  DateTime today, {
  required DateTime first,
  required DateTime last,
}) {
  final t = _day(today);
  final all = [
    ('Last 4 weeks', _addDays(t, -27), t),
    ('This month', DateTime(t.year, t.month), DateTime(t.year, t.month + 1, 0)),
    ('Last month', DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0)),
    ('This year', DateTime(t.year), DateTime(t.year, 12, 31)),
  ];
  return [
    for (final (label, from, to) in all)
      if (!to.isBefore(_day(first)) && !from.isAfter(_day(last)))
        (
          label,
          DateTimeRange(
            start: from.isBefore(_day(first)) ? _day(first) : from,
            end: to.isAfter(_day(last)) ? _day(last) : to,
          ),
        ),
  ];
}

/// A range of days chosen on a calendar grid, for a wide window: two
/// months side by side (one when there is no room), ready-made ranges
/// beside them, and Cancel and Apply. Returns the range, [allDates] when
/// "All dates" is applied, or null when cancelled.
///
/// Days in [marked] carry a dot, explained by [markedHint].
Future<DateTimeRange?> showDateRangeDialog(
  BuildContext context, {
  required String title,
  required DateTime firstDate,
  required DateTime lastDate,
  required DateTime today,
  DateTimeRange? initial,
  Set<DateTime> marked = const {},
  String markedHint = '',
}) => showDialog<DateTimeRange>(
  context: context,
  animationStyle: reduceAppMotion(context) ? AnimationStyle.noAnimation : null,
  builder: (_) => DateRangeDialog(
    title: title,
    firstDate: _day(firstDate),
    lastDate: _day(lastDate),
    today: _day(today),
    initial: initial,
    marked: {for (final d in marked) _day(d)},
    markedHint: markedHint,
  ),
);

class DateRangeDialog extends StatefulWidget {
  final String title, markedHint;
  final DateTime firstDate, lastDate, today;
  final DateTimeRange? initial;
  final Set<DateTime> marked;
  const DateRangeDialog({
    super.key,
    required this.title,
    required this.firstDate,
    required this.lastDate,
    required this.today,
    this.initial,
    this.marked = const {},
    this.markedHint = '',
  });
  @override
  State<DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<DateRangeDialog> {
  static const cell = 40.0, monthWidth = cell * 7, monthGap = 36.0;
  static const sideWidth = 168.0, edge = 24.0;

  /// The dialog's width with two months, and with one.
  static const wide = edge * 3 + sideWidth + 1 + monthWidth * 2 + monthGap + 24;
  static const narrow = edge * 3 + sideWidth + 1 + monthWidth + 24;

  final grid = FocusNode(debugLabel: 'calendar');
  DateTime? start, end, hover;
  bool all = false;

  /// Whether the keyboard is moving [cursor], so its ring is drawn.
  bool keys = false;
  late DateTime cursor;

  /// The first month shown.
  late DateTime month;
  int shown = 2;

  DateTime get first => widget.firstDate;
  DateTime get last => widget.lastDate;
  bool allowed(DateTime d) => !d.isBefore(first) && !d.isAfter(last);
  DateTime clampDay(DateTime d) => d.isBefore(first)
      ? first
      : d.isAfter(last)
      ? last
      : d;

  @override
  void initState() {
    super.initState();
    final range = widget.initial;
    if (range != null) {
      start = clampDay(_day(range.start));
      end = clampDay(_day(range.end));
    }
    cursor = start ?? clampDay(widget.today);
    // With nothing chosen, this month sits on the right: a filter looks
    // back more often than forward.
    month = start != null
        ? DateTime(start!.year, start!.month)
        : _addMonths(DateTime(cursor.year, cursor.month), -1);
  }

  @override
  void dispose() {
    grid.dispose();
    super.dispose();
  }

  DateTime get firstMonth => DateTime(first.year, first.month);
  DateTime get lastMonth => DateTime(last.year, last.month);
  bool get canGoBack => month.isAfter(firstMonth);
  bool get canGoOn => _addMonths(month, shown - 1).isBefore(lastMonth);

  /// [month] kept inside the allowed months, for the number [shown].
  DateTime fitMonth(DateTime m) {
    final latest = _addMonths(lastMonth, 1 - shown);
    if (m.isAfter(latest)) m = latest;
    if (m.isBefore(firstMonth)) m = firstMonth;
    return m;
  }

  void turn(int months) => setState(() {
    month = fitMonth(_addMonths(month, months));
  });

  /// Brings [d] into view if it is not in a month already shown.
  void reveal(DateTime d) {
    final m = DateTime(d.year, d.month);
    if (m.isBefore(month)) {
      month = fitMonth(m);
    } else if (m.isAfter(_addMonths(month, shown - 1))) {
      month = fitMonth(_addMonths(m, 1 - shown));
    }
  }

  void choose(DateTime d) {
    if (!allowed(d)) return;
    setState(() {
      all = false;
      cursor = d;
      if (start == null || end != null) {
        start = d;
        end = null;
      } else if (d.isBefore(start!)) {
        end = start;
        start = d;
      } else {
        end = d;
      }
    });
  }

  void useShortcut(DateTimeRange range) => setState(() {
    all = false;
    keys = false;
    start = range.start;
    end = range.end;
    cursor = range.start;
    // Show the end of a long range, where the recent services are.
    month = fitMonth(
      _addMonths(DateTime(range.end.year, range.end.month), 1 - shown),
    );
    if (DateTime(range.start.year, range.start.month).isAfter(month)) {
      month = fitMonth(DateTime(range.start.year, range.start.month));
    }
  });

  /// The days to fill: the chosen range, or while only the first day is
  /// chosen, from it to the day pointed at.
  (DateTime, DateTime)? get filled {
    final a = start;
    if (a == null) return null;
    final b = end ?? (keys ? cursor : hover) ?? a;
    return b.isBefore(a) ? (b, a) : (a, b);
  }

  KeyEventResult onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    DateTime? to;
    if (key == LogicalKeyboardKey.arrowLeft) to = _addDays(cursor, -1);
    if (key == LogicalKeyboardKey.arrowRight) to = _addDays(cursor, 1);
    if (key == LogicalKeyboardKey.arrowUp) to = _addDays(cursor, -7);
    if (key == LogicalKeyboardKey.arrowDown) to = _addDays(cursor, 7);
    if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      final by = key == LogicalKeyboardKey.pageUp ? -1 : 1;
      final m = DateTime(cursor.year, cursor.month + by);
      to = DateTime(
        m.year,
        m.month,
        cursor.day > _daysIn(m) ? _daysIn(m) : cursor.day,
      );
    }
    if (to != null) {
      final day = clampDay(to);
      setState(() {
        // The first key only shows where the keyboard is.
        if (keys) cursor = day;
        keys = true;
        reveal(cursor);
      });
      return KeyEventResult.handled;
    }
    // Enter and Space belong to a focused button; on the calendar they
    // choose the day the ring is on.
    final chooses =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (chooses && grid.hasPrimaryFocus) {
      if (keys) {
        choose(cursor);
        setState(() => keys = true);
      } else {
        setState(() {
          keys = true;
          reveal(cursor);
        });
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final theme = Theme.of(context);
    final window = MediaQuery.sizeOf(context);
    // Dialog insets take 40 px each side.
    final two = window.width - 80 >= wide;
    if ((two ? 2 : 1) != shown) {
      shown = two ? 2 : 1;
      month = fitMonth(month);
      reveal(start ?? cursor);
    }
    final complete = all || (start != null && end != null);
    final summary = all
        ? 'All dates'
        : start == null
        ? 'Choose the first day, then the last.'
        : end == null
        ? 'From ${longDate(start!)}. Choose the last day.'
        : dateRangeWords(start!, end!);
    final shortcuts = dateRangeShortcuts(
      widget.today,
      first: first,
      last: last,
    );
    return Dialog(
      key: const ValueKey('date-range-dialog'),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: two ? wide : narrow),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(edge, 22, edge, 14),
                child: Text(widget.title, style: theme.textTheme.titleLarge),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              Flexible(
                child: SingleChildScrollView(
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
                          child: SizedBox(
                            width: sideWidth + edge - 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                                  child: PaneLabel('Quick ranges'),
                                ),
                                for (final (label, range) in shortcuts)
                                  shortcut(
                                    label,
                                    selected:
                                        !all &&
                                        start == range.start &&
                                        end == range.end,
                                    onTap: () => useShortcut(range),
                                  ),
                                shortcut(
                                  'All dates',
                                  selected: all,
                                  onTap: () => setState(() {
                                    all = true;
                                    keys = false;
                                    start = end = null;
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: colors.border,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              edge,
                              12,
                              edge,
                              14,
                            ),
                            child: calendar(two),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(edge, 14, edge, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          summary,
                          key: const ValueKey('date-range-summary'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: complete ? colors.text : colors.muted,
                            fontWeight: complete
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('date-range-apply'),
                      onPressed: !complete
                          ? null
                          : () => Navigator.pop(
                              context,
                              all
                                  ? allDates
                                  : DateTimeRange(start: start!, end: end!),
                            ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget shortcut(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: colors.highContrast ? .28 : .16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget calendar(bool two) {
    final colors = appColors(context);
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.muted, height: 1.3);
    return Focus(
      focusNode: grid,
      autofocus: true,
      child: MouseRegion(
        onExit: (_) => setState(() => hover = null),
        // The figures keep to their cells when the system text is large.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  monthGrid(month, back: true, forward: !two),
                  if (two) ...[
                    const SizedBox(width: monthGap),
                    monthGrid(_addMonths(month, 1), back: false, forward: true),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: two ? monthWidth * 2 + monthGap : monthWidth,
                child: Row(
                  children: [
                    if (widget.marked.isNotEmpty &&
                        widget.markedHint.isNotEmpty) ...[
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(left: 17, right: 8),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(widget.markedHint, style: muted),
                    ],
                    const Spacer(),
                    if (two)
                      Text('Arrow keys move · Enter chooses', style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget monthGrid(DateTime m, {required bool back, required bool forward}) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final words = MaterialLocalizations.of(context);
    // Monday is the first column, as on a UK calendar.
    final firstColumn = m.weekday - DateTime.monday;
    final days = _daysIn(m);
    final rows = <Widget>[];
    for (var slot = 0; slot < 42; slot += 7) {
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = slot; i < slot + 7; i++)
              i < firstColumn || i >= firstColumn + days
                  ? const SizedBox(width: cell, height: cell)
                  : dayCell(
                      DateTime(m.year, m.month, i - firstColumn + 1),
                      column: i % 7,
                      days: days,
                    ),
          ],
        ),
      );
    }
    Widget arrow(bool show, bool enabled, IconData icon, String tip, int by) =>
        SizedBox(
          width: cell,
          height: cell,
          child: !show
              ? null
              : IconButton(
                  key: ValueKey(by < 0 ? 'month-back' : 'month-forward'),
                  tooltip: tip,
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                  onPressed: enabled ? () => turn(by) : null,
                  icon: Icon(icon),
                ),
        );
    return SizedBox(
      width: monthWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              arrow(back, canGoBack, Icons.chevron_left, 'Previous month', -1),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    '${_monthNames[m.month - 1]} ${m.year}',
                    key: ValueKey('month-${m.year}-${m.month}'),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              arrow(forward, canGoOn, Icons.chevron_right, 'Next month', 1),
            ],
          ),
          const SizedBox(height: 4),
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 7; i++)
                  SizedBox(
                    width: cell,
                    height: 28,
                    child: Center(
                      child: Text(
                        // narrowWeekdays starts on Sunday.
                        words.narrowWeekdays[(i + 1) % 7],
                        style: text.bodySmall?.copyWith(
                          color: colors.muted,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget dayCell(DateTime d, {required int column, required int days}) {
    final colors = appColors(context);
    final strong = colors.highContrast;
    final enabled = allowed(d);
    final range = filled;
    final inRange =
        range != null &&
        range.$1 != range.$2 &&
        !d.isBefore(range.$1) &&
        !d.isAfter(range.$2);
    final isEnd = d == start || d == end;
    final preview = end == null;
    final pointed = enabled && !isEnd && d == hover && !keys;
    final ring = keys && d == cursor;
    final today = d == widget.today;
    const round = Radius.circular(18);
    final bandStarts = inRange && d == range.$1;
    final bandEnds = inRange && d == range.$2;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: isEnd || (inRange && !preview),
      label: '${longDate(d)}${today ? ', today' : ''}',
      excludeSemantics: true,
      onTap: enabled ? () => choose(d) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() {
          hover = enabled ? d : null;
          keys = false;
        }),
        child: GestureDetector(
          key: ValueKey('day-${d.year}-${d.month}-${d.day}'),
          behavior: HitTestBehavior.opaque,
          onTap: !enabled
              ? null
              : () {
                  keys = false;
                  grid.requestFocus();
                  choose(d);
                },
          child: SizedBox(
            width: cell,
            height: cell,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (inRange)
                  Positioned(
                    left: bandStarts ? cell / 2 : 0,
                    right: bandEnds ? cell / 2 : 0,
                    top: 2,
                    bottom: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(
                          alpha: (preview ? .10 : .20) * (strong ? 1.6 : 1),
                        ),
                        borderRadius: BorderRadius.horizontal(
                          left: !bandStarts && (column == 0 || d.day == 1)
                              ? round
                              : Radius.zero,
                          right: !bandEnds && (column == 6 || d.day == days)
                              ? round
                              : Radius.zero,
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isEnd
                        ? colors.accent
                        : pointed
                        ? colors.text.withValues(alpha: .10)
                        : null,
                    border: ring
                        ? Border.all(color: colors.text, width: 2)
                        : today && !isEnd
                        ? Border.all(
                            color: colors.accent,
                            width: strong ? 2 : 1.5,
                          )
                        : pointed && preview && start != null
                        ? Border.all(color: colors.accent, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    '${d.day}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      height: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: isEnd || today
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isEnd
                          ? readable(colors.accent)
                          : enabled
                          ? colors.text
                          : colors.muted.withValues(alpha: .45),
                    ),
                  ),
                ),
                if (widget.marked.contains(d))
                  Positioned(
                    bottom: 5,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isEnd ? readable(colors.accent) : colors.accent,
                        shape: BoxShape.circle,
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
}
