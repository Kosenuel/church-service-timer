import 'dart:io';
import '../test/settings/church_profile_and_backup_cases.dart';

void main() {
  for (final e in revision07Cases.entries) {
    e.value();
    stdout.writeln('PASS ${e.key}');
  }
  stdout.writeln('${revision07Cases.length} revision 0.7 checks passed.');
}
