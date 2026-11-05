import 'dart:io';
import '../test/programs/program_grouping_cases.dart';

void main() {
  for (final e in revision06Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision06Cases.length} revision 0.6 checks passed.');
}
