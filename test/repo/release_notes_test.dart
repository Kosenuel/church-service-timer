import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// scripts/release_notes.py is what release.yml uses for a release's notes,
/// test versions (0.36.0-beta.1) included.
void main() {
  const changelog = '''# Changelog

## Unreleased

- Not released yet.

## 0.36.0-beta.2, 02/December/2026

- Beta two entry.

## 0.36.0-beta.1, 01/December/2026

- Beta one entry.
  - Sub entry.

## 0.36.0, 05/December/2026

- Stable entry.

## 0.35.0, 21/November/2026

- Older entry.
''';

  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('release-notes');
    path = '${dir.path}/CHANGELOG.md';
    File(path).writeAsStringSync(changelog);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProcessResult notes(String version) =>
      Process.runSync('python3', ['scripts/release_notes.py', version, path]);

  test('a pre-release heading gives only its own section', () {
    final one = notes('0.36.0-beta.1');
    expect(one.exitCode, 0);
    expect(one.stdout.toString().trim(), '- Beta one entry.\n  - Sub entry.');
    final two = notes('0.36.0-beta.2');
    expect(two.stdout.toString().trim(), '- Beta two entry.');
  });

  test('a stable version does not pick up its betas, or the other way', () {
    expect(notes('0.36.0').stdout.toString().trim(), '- Stable entry.');
    expect(notes('0.35.0').stdout.toString().trim(), '- Older entry.');
  });

  test('a version with no section fails', () {
    expect(notes('0.36.0-beta.3').exitCode, isNot(0));
    expect(notes('0.36.0-beta').exitCode, isNot(0));
    expect(notes('0.36').exitCode, isNot(0));
  });
}
