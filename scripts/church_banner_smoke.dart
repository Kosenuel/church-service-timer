import 'dart:io';
import '../test/settings/church_banner_cases.dart';

void main() {
  for (final e in revision08Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision08Cases.length} revision 0.8 checks passed.');
}
