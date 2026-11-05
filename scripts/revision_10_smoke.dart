import 'dart:io';
import '../test/revision_10_cases.dart';

void main() {
  for (final e in revision10Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision10Cases.length} revision 0.10 checks passed.');
}
