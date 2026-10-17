import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/feedback_message.dart';
import 'feature_cases.dart' show equal, rejects;

final revision09Cases = <String, void Function()>{
  'Feedback normalizes fields and includes the installed version': () {
    final f = FeedbackMessage(
      title: '  Timer stopped  ',
      message: ' First line\r\nSecond line ',
      contact: ' +234 800 123 4567 ',
      version: '3.2.1 (42)',
    );
    equal(f.title, 'Timer stopped');
    equal(f.message, 'First line\nSecond line');
    equal(f.contact, '+234 800 123 4567');
    equal(f.subject, '$appName feedback: Timer stopped');
    equal(f.body.contains('Version: 3.2.1 (42)'), true);
  },
  'Feedback requires title, message and contact': () {
    for (final values in [
      [' ', 'message', 'contact'],
      ['title', '\n', 'contact'],
      ['title', 'message', ' '],
    ]) {
      rejects(
        () => FeedbackMessage(
          title: values[0],
          message: values[1],
          contact: values[2],
          version: appVersion,
        ),
      );
    }
  },
  'Feedback enforces limits and forbids control characters in single-line fields':
      () {
        for (final value in ['a' * 121, 'Hello\nBcc: other', 'Hello\x00']) {
          rejects(() => FeedbackMessage.checked(value, 120, 'Title'));
          rejects(() => FeedbackMessage.checked(value, 120, 'Contact'));
        }
        rejects(
          () => FeedbackMessage.checked(
            'a' * 4001,
            4000,
            'Message',
            multiline: true,
          ),
        );
        rejects(
          () => FeedbackMessage.checked(
            'bad\x01message',
            4000,
            'Message',
            multiline: true,
          ),
        );
      },
  'Feedback supports multiline Unicode content and literal URL punctuation':
      () {
        final f = FeedbackMessage(
          title: 'Église & timer?',
          message: 'Thanks 🙏\nText: a+b & c=d #tag',
          contact: 'operator@example.com',
          version: appVersion,
        );
        equal(f.body.contains('Thanks 🙏\nText: a+b & c=d #tag'), true);
        equal(f.contact, 'operator@example.com');
      },
  'Copyable feedback includes the fixed recipient and complete complaint': () {
    final f = FeedbackMessage(
      title: 'Pause',
      message: 'Please improve pause.',
      contact: 'operator@example.com',
      version: appVersion,
    );
    equal(feedbackRecipient, 'immanuelproton@gmail.com');
    equal(
      f.copyText,
      'To: immanuelproton@gmail.com\nSubject: Church Service Timer feedback: Pause\n\nTitle: Pause\n\nMessage:\nPlease improve pause.\n\nContact: operator@example.com\n\nApp: Church Service Timer\nVersion: $appVersion',
    );
  },
};
