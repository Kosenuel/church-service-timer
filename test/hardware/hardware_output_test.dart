import 'package:flutter_test/flutter_test.dart';

import 'hardware_output_cases.dart';

void main() {
  for (final entry in hardwareOutputCases.entries) {
    test(entry.key, entry.value);
  }
}
