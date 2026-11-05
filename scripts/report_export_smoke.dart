import 'dart:io';
import '../test/reports/report_export_and_end_screen_cases.dart';

void main() {
  for (final entry in revision04Cases.entries) {
    entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
  stdout.writeln('${revision04Cases.length} revision 0.4 checks passed.');
}
