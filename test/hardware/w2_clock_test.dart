import 'package:flutter_test/flutter_test.dart';
import 'w2_clock_cases.dart';

void main() {
  for (final entry in w2ClockCases.entries) {
    test(entry.key, entry.value);
  }
}
