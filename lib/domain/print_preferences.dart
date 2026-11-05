import 'package:church_service_timer/domain/domain.dart';

class PrintPreferences {
  final bool watermark, inkSaving;
  const PrintPreferences({this.watermark = true, this.inkSaving = false});
  factory PrintPreferences.fromJson(Json j) => PrintPreferences(
    watermark: boolSetting(j['watermark'] ?? true),
    inkSaving: boolSetting(j['inkSaving'] ?? false),
  );
  Json toJson() => {'watermark': watermark, 'inkSaving': inkSaving};
}

String preparedDateLabel(int wall) {
  final d = DateTime.fromMillisecondsSinceEpoch(wall);
  const months = [
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
  final zone = d.timeZoneOffset;
  final offset =
      '${zone.isNegative ? '-' : '+'}${zone.inHours.abs().toString().padLeft(2, '0')}:${(zone.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${printClockLabel(wall)} (UTC$offset)';
}
