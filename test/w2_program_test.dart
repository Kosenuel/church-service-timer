import 'package:flutter_test/flutter_test.dart';
import 'w2_program_cases.dart';

void main() {
  for (final entry in w2ProgramCases.entries) {
    test(entry.key, entry.value);
  }
}
