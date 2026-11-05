import 'dart:io';
import '../test/revision_05_cases.dart';

void main() {
  for (final e in revision05Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision05Cases.length} revision 0.5 checks passed.');
}
