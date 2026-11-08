import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fonts saved before 0.28 open with their new ids', () {
    for (final (old, now) in [
      ('cuekeeper_matrix', 'i-proton_matrix'),
      ('cuekeeper_sq_matrix', 'i-proton_sq_matrix'),
      ('service_serif', 'i-proton_matrix'),
      ('times_new_roman', 'tinos'),
    ]) {
      final layout = TextLayout.fromJson({
        'text': 'WELCOME',
        'bold': false,
        'italic': false,
        'effect': 'static',
        'align': 'center',
        'speed': 12,
        'height': 2,
        'font': old,
      });
      expect(layout.font, now, reason: old);
      expect(layout.toJson()['font'], now);
    }
  });

  test('The old project name appears only where it must', () {
    // The app's old working name is kept only to read old files, in the
    // release history (which records past versions as they were), in the
    // file format note about old ids, and in these tests.
    const allowed = {
      'lib/domain/service_features.dart',
      'docs/TEMPLATE-FORMAT.md',
      'test/repo/naming_test.dart',
    };
    final found = <String>[];
    for (final root in [
      'lib',
      'test',
      'android/app/src',
      'android/app/build.gradle.kts',
      'scripts',
      'assets',
      'examples',
      'docs',
      'README.md',
      'CHANGELOG.md',
      'pubspec.yaml',
    ]) {
      final entities = FileSystemEntity.isDirectorySync(root)
          ? Directory(root).listSync(recursive: true)
          : [File(root)];
      for (final e in entities.whereType<File>()) {
        final path = e.path.replaceAll(r'\', '/');
        if (path.startsWith('docs/history/') ||
            allowed.contains(path) ||
            path.endsWith('.png') ||
            path.endsWith('.ttf') ||
            path.endsWith('.otf'))
          continue;
        if (latin1
            .decode(e.readAsBytesSync())
            .toLowerCase()
            .contains('cuekeeper'))
          found.add(path);
      }
    }
    expect(found, isEmpty);
  });
}
