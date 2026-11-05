import 'dart:io';
import '../test/revision_07_cases.dart';

void main() {
  for (final e in revision07Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision07Cases.length} revision 0.7 checks passed.');
}
