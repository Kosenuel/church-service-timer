import 'dart:io';
import '../test/feature_cases.dart';

void main() {
  for (final entry in featureCases.entries) {
    entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
  stdout.writeln('${featureCases.length} feature checks passed.');
}
