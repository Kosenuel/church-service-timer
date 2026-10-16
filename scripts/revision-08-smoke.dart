import 'dart:io';
import '../test/revision_08_cases.dart';

void main() {
  for (final e in revision08Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision08Cases.length} revision 0.8 checks passed.');
}
