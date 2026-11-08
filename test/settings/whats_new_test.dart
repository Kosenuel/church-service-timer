import 'package:church_service_timer/settings/whats_new_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseChangelog keeps release order and cleans markdown', () {
    final releases = parseChangelog('''
# Changelog

## Unreleased
- **Bold** item with `code`
  - folded detail
- A [link](https://example.com)
- Settings → About ✕

## 0.25.0, 7/November/2026
- Dated entry

## 0.24.0 - 2026-10-01
- Older entry
''');
    expect(releases.map((r) => r.heading), [
      'Unreleased',
      '0.25.0, 7 November 2026',
      '0.24.0 - 2026-10-01',
    ]);
    expect(releases.first.entries, [
      'Bold item with code folded detail',
      'A link',
      'Settings › About ×',
    ]);
    expect(releases.last.entries, ['Older entry']);
  });
}
