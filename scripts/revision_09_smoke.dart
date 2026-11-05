import 'dart:io';
import '../test/revision_09_cases.dart';

void main() {
  for (final e in revision09Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision09Cases.length} revision 0.9 checks passed.');
}
