import 'package:flutter_test/flutter_test.dart';
import '../support/w2_port.dart';

void main() {
  test(
    'Scheduling a start sends the pre-service countdown to the sign',
    () async {
      final port = W2Port();
      final c = await setup(port, started: false);
      expect(c.state.session.phase, 'ready');
      expect(c.hardware.held, isTrue, reason: 'Ready keeps the sign held');
      port.sent.clear();
      await c.act('schedule', value: c.now.wall + 20 * 60000);
      await flush();
      expect(c.hardware.held, isFalse);
      expect(port.sent, isNotEmpty);
      expect(port.sent.last.deadline, c.state.session.startsAtWall);
    },
  );
}
