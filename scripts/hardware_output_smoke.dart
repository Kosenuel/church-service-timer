import 'dart:io';

import '../test/hardware/hardware_output_cases.dart';

void main() {
  for (final entry in hardwareOutputCases.entries) {
    entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
  stdout.writeln(
    '${hardwareOutputCases.length} hardware output checks passed.',
  );
}
