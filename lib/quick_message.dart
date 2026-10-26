part of 'domain.dart';

/// Mobile-stage content. Never converted to LED glyphs or hardware programs.
class QuickMessage {
  final String headline, body, align, palette;
  final bool bold, italic, requestSeen;
  final int seconds;
  final double scale;
  const QuickMessage({
    this.headline = '',
    required this.body,
    this.bold = false,
    this.italic = false,
    this.requestSeen = false,
    this.align = 'center',
    this.palette = 'white',
    this.seconds = 10,
    this.scale = 1,
  });
  int get length => headline.runes.length + body.runes.length;
  String get name => headline.isEmpty ? body : headline;
  void validate() {
    require(body.trim().isNotEmpty, 'Enter a message.');
    require(
      !headline.contains('\n') && body.split('\n').length <= 6,
      'Use one headline and at most six message lines for a readable stage screen.',
    );
    require(
      length <= 160,
      'Keep the headline and message within 160 characters.',
    );
    require(
      headline.runes.length <= 48,
      'Keep the headline within 48 characters.',
    );
    require(
      {'left', 'center', 'right'}.contains(align),
      'Choose an alignment.',
    );
    require(
      {'white', 'amber', 'sky', 'mint'}.contains(palette),
      'Choose a colour preset.',
    );
    readMessageDuration(seconds);
    require({0.85, 1.0, 1.15}.contains(scale), 'Choose a text size.');
  }

  factory QuickMessage.fromJson(Json j) {
    final message = QuickMessage(
      headline: j['headline'] as String? ?? '',
      body: j['body'] as String,
      bold: boolSetting(j['bold'] ?? false),
      italic: boolSetting(j['italic'] ?? false),
      requestSeen: boolSetting(j['requestSeen'] ?? false),
      align: j['align'] as String? ?? 'center',
      palette: j['palette'] as String? ?? 'white',
      seconds: j['seconds'] as int? ?? 10,
      scale: (j['scale'] as num? ?? 1).toDouble(),
    );
    message.validate();
    return message;
  }
  Json toJson() => {
    'headline': headline,
    'body': body,
    'bold': bold,
    'italic': italic,
    'requestSeen': requestSeen,
    'align': align,
    'palette': palette,
    'seconds': seconds,
    'scale': scale,
  };
}

const defaultQuickMessages = [
  QuickMessage(
    headline: 'PLEASE WRAP UP',
    body:
        'We have five minutes before the next session. Please bring your current point to a close.',
    seconds: 15,
    palette: 'amber',
  ),
  QuickMessage(
    headline: 'ANNOUNCEMENT TO MAKE',
    body:
        'Please remind everyone that refreshments will be available immediately after the service.',
    seconds: 30,
  ),
  QuickMessage(
    headline: 'MICROPHONE CHECK',
    body:
        'Please hold the microphone closer and pause briefly while the sound team adjusts your level.',
    seconds: 15,
    palette: 'sky',
  ),
  QuickMessage(
    headline: 'PLEASE WAIT',
    body: 'We are preparing the next segment. Thank you for your patience.',
    palette: 'mint',
  ),
];

String serviceDateLabel(int milliseconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
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
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}

String printClockLabel(int milliseconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
