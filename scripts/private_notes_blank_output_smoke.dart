import 'dart:io';
import '../test/domain/private_notes_and_blank_output_cases.dart';

void main() {
  for (final e in revision10Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision10Cases.length} revision 0.10 checks passed.');
}
