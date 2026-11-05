import 'dart:io';
import '../test/hardware/w2_program_cases.dart';

void main() {
  for (final entry in w2ProgramCases.entries) {
    entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
  stdout.writeln('${w2ProgramCases.length} W2 program checks passed.');
}
