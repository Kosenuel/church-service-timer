import 'domain.dart';

const feedbackRecipient = 'kosenuel@gmail.com';

class FeedbackMessage {
  final String title, message, contact, version;
  FeedbackMessage({
    required String title,
    required String message,
    required String contact,
    required this.version,
  }) : title = checked(title, 120, 'Title'),
       message = checked(message, 4000, 'Message', multiline: true),
       contact = checked(contact, 120, 'Contact');

  static String checked(
    String value,
    int limit,
    String label, {
    bool multiline = false,
  }) {
    final text = value.replaceAll('\r\n', '\n').trim();
    require(text.isNotEmpty, 'Enter a ${label.toLowerCase()}.');
    require(
      text.runes.length <= limit,
      '$label must be $limit characters or fewer.',
    );
    require(
      !RegExp(
        multiline ? r'[\x00-\x08\x0b-\x1f\x7f]' : r'[\x00-\x1f\x7f]',
      ).hasMatch(text),
      '$label contains unsupported characters.',
    );
    return text;
  }

  String get subject => '$appName feedback: $title';
  String get body =>
      'Title: $title\n\nMessage:\n$message\n\nContact: $contact\n\nApp: $appName\nVersion: $version';
  String get copyText => 'To: $feedbackRecipient\nSubject: $subject\n\n$body';
}
