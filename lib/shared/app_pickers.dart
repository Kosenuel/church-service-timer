import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _fullDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Flutter's English wording with dates written day first, as the rest
/// of the app writes them: "Fri 20 Nov 2026" over the calendar and
/// 20/11/2026 when a date is typed. Everything else is unchanged, so the
/// pickers keep their own words and the week still starts where the
/// app's other calendar starts it.
class DayFirstLocalizations extends DefaultMaterialLocalizations {
  const DayFirstLocalizations();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "Fri 20 Nov 2026".
  @override
  String formatMediumDate(DateTime date) =>
      '${_days[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';

  /// "Friday 20 November 2026".
  @override
  String formatFullDate(DateTime date) =>
      '${_fullDays[date.weekday - 1]} ${date.day} ${formatMonthYear(date)}';

  /// "20 Nov": the short form, as in a range "20 Nov – 4 Dec".
  @override
  String formatShortMonthDay(DateTime date) =>
      '${date.day} ${_months[date.month - 1]}';

  /// "20 Nov 2026".
  @override
  String formatShortDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  /// 20/11/2026.
  @override
  String formatCompactDate(DateTime date) =>
      '${_two(date.day)}/${_two(date.month)}/${date.year}';

  @override
  DateTime? parseCompactDate(String? inputString) {
    final parts = inputString?.trim().split('/');
    if (parts == null || parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (parts[2].length != 4 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    if (day > DateUtils.getDaysInMonth(year, month)) return null;
    return DateTime(year, month, day);
  }

  @override
  String get dateHelpText => 'dd/mm/yyyy';

  @override
  String get invalidDateFormatLabel => 'Write the date as dd/mm/yyyy.';

  static const delegate = _DayFirstDelegate();
}

class _DayFirstDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _DayFirstDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<MaterialLocalizations> load(Locale locale) async =>
      const DayFirstLocalizations();
  @override
  bool shouldReload(_DayFirstDelegate old) => false;
}

/// The app's look for Flutter's date and time pickers: the theme's
/// surface, border and accent instead of Material's tinted defaults, with
/// the same rounded, outlined card as the app's other dialogs and the
/// reports calendar.
ThemeData appPickerTheme(BuildContext context) {
  final theme = Theme.of(context);
  final p = appColors(context);
  final onAccent = readable(p.accent);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
    side: BorderSide(color: p.border),
  );
  WidgetStateProperty<Color?> selected(Color on, Color? off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );
  // The time picker takes these as a colour that changes with its state.
  Color selectedColour(Color on, Color off) => WidgetStateColor.resolveWith(
    (states) => states.contains(WidgetState.selected) ? on : off,
  );
  final disabled = p.muted.withValues(alpha: .45);
  final input = InputDecorationTheme(
    filled: true,
    fillColor: p.input,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.accent, width: 2),
    ),
  );
  return theme.copyWith(
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      headerBackgroundColor: p.surface,
      headerForegroundColor: p.text,
      headerHelpStyle: theme.textTheme.labelLarge?.copyWith(
        color: p.muted,
        fontWeight: FontWeight.w600,
      ),
      dividerColor: p.border,
      weekdayStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
      dayStyle: const TextStyle(
        fontSize: 14,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? onAccent
            : states.contains(WidgetState.disabled)
            ? disabled
            : p.text,
      ),
      dayBackgroundColor: selected(p.accent, null),
      dayOverlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? p.text.withValues(alpha: .10)
            : null,
      ),
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? onAccent
            : states.contains(WidgetState.disabled)
            ? disabled
            : p.text,
      ),
      todayBackgroundColor: selected(p.accent, null),
      todayBorder: BorderSide(color: p.accent, width: p.highContrast ? 2 : 1.5),
      yearForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? onAccent
            : states.contains(WidgetState.disabled)
            ? disabled
            : p.text,
      ),
      yearBackgroundColor: selected(p.accent, null),
      rangePickerBackgroundColor: p.surface,
      rangePickerSurfaceTintColor: Colors.transparent,
      rangePickerHeaderBackgroundColor: p.surface,
      rangePickerHeaderForegroundColor: p.text,
      rangeSelectionBackgroundColor: p.accent.withValues(
        alpha: p.highContrast ? .32 : .20,
      ),
      inputDecorationTheme: input,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: p.surface,
      shape: shape,
      helpTextStyle: theme.textTheme.labelLarge?.copyWith(
        color: p.muted,
        fontWeight: FontWeight.w600,
      ),
      hourMinuteColor: selectedColour(
        p.accent.withValues(alpha: p.highContrast ? .32 : .20),
        p.input,
      ),
      hourMinuteTextColor: p.text,
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
      dayPeriodColor: selectedColour(
        p.accent.withValues(alpha: p.highContrast ? .32 : .20),
        Colors.transparent,
      ),
      dayPeriodTextColor: p.text,
      dayPeriodBorderSide: BorderSide(color: p.border),
      dialBackgroundColor: p.input,
      dialHandColor: p.accent,
      dialTextColor: selectedColour(onAccent, p.text),
      entryModeIconColor: p.muted,
      timeSelectorSeparatorColor: WidgetStatePropertyAll(p.text),
    ),
  );
}

/// Wraps a picker in [appPickerTheme] and [DayFirstLocalizations]. With
/// [use24Hour] set, times are shown and chosen on a 24-hour clock.
///
/// A calendar ([dates]) stands upright, its header over the month, in any
/// window tall enough for it: Flutter lays it on its side whenever the
/// window is wider than it is tall, as a computer's always is, and the
/// side header has room for only half of "Fri 20 Nov 2026". When it must
/// lie on its side, as on a phone held sideways, the date is written
/// smaller so it fits on two lines.
Widget _pickerFrame(
  BuildContext context,
  Widget? child, {
  bool? use24Hour,
  bool dates = false,
}) {
  final media = MediaQuery.of(context);
  var data = media;
  if (use24Hour != null) data = data.copyWith(alwaysUse24HourFormat: use24Hour);
  var theme = appPickerTheme(context);
  if (dates) {
    final size = media.size;
    if (size.width > size.height && size.height >= _uprightCalendarHeight) {
      data = data.copyWith(size: Size(size.height, size.width));
    } else if (size.width > size.height) {
      theme = theme.copyWith(
        datePickerTheme: theme.datePickerTheme.copyWith(
          headerHeadlineStyle: theme.textTheme.headlineSmall,
        ),
      );
    }
  }
  return MediaQuery(
    data: data,
    child: Theme(
      data: theme,
      child: Localizations.override(
        context: context,
        delegates: const [DayFirstLocalizations.delegate],
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

/// The upright calendar is 568 tall, with 24 above and below it.
const _uprightCalendarHeight = 568 + 48.0;

/// One day, from Flutter's calendar in the app's look and written day
/// first. Every call site uses this, not [showDatePicker]. [currentDate]
/// is the day ringed as today: the app's own clock.
Future<DateTime?> showAppDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  String? helpText,
}) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: firstDate,
  lastDate: lastDate,
  currentDate: currentDate,
  helpText: helpText,
  // Typed dates are written dd/mm/yyyy, as the hint under the field says.
  fieldHintText: 'dd/mm/yyyy',
  builder: (context, child) => _pickerFrame(context, child, dates: true),
);

/// A range of days on a phone, in the same look as [showAppDatePicker].
Future<DateTimeRange?> showAppDateRangePicker(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? helpText,
  String? saveText,
  String? fieldStartLabelText,
  String? fieldEndLabelText,
  String? fieldStartHintText,
  String? fieldEndHintText,
}) => showDateRangePicker(
  context: context,
  firstDate: firstDate,
  lastDate: lastDate,
  initialDateRange: initialDateRange,
  helpText: helpText,
  saveText: saveText,
  fieldStartLabelText: fieldStartLabelText,
  fieldEndLabelText: fieldEndLabelText,
  fieldStartHintText: fieldStartHintText,
  fieldEndHintText: fieldEndHintText,
  builder: (context, child) => _pickerFrame(context, child),
);

/// A time of day, from Flutter's clock in the app's look. [use24Hour]
/// follows the app's clock format, which is 24-hour unless the church
/// chose 12-hour. On a computer ([typed]) the hours and minutes start as
/// fields to type into, which suits a keyboard better than a dial; the
/// icon in the corner still switches to the dial.
Future<TimeOfDay?> showAppTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  required bool use24Hour,
  bool typed = false,
  String? helpText,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  helpText: helpText,
  initialEntryMode: typed
      ? TimePickerEntryMode.input
      : TimePickerEntryMode.dial,
  builder: (context, child) =>
      _pickerFrame(context, child, use24Hour: use24Hour),
);
