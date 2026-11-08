import 'dart:async';

import 'package:flutter/services.dart';

import 'fake_port.dart';

/// Fake devices that record exports and feedback emails.

class ExportPort extends FakePort {
  final exports = <Map<String, String>>[];
  @override
  Future<void> exportFile(String filename, String content) async {
    exports.add({'filename': filename, 'content': content});
  }
}

class FeedbackPort extends FakePort {
  bool available = true, failEmail = false;
  final messages = <Map<String, String>>[];
  @override
  Future<bool> composeFeedback(String subject, String body) async {
    if (failEmail) throw PlatformException(code: 'EMAIL');
    messages.add({'subject': subject, 'body': body});
    return available;
  }
}
