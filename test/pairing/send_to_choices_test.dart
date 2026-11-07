import 'package:church_service_timer/pairing/stage_screen_views.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final groups = {'p1': 'choir', 'p2': 'choir', 'p3': 'preacher'};
  List<(String, String, bool)> choices(
    List<({String id, String name})> screens,
    String current,
  ) => [
    for (final o in quickAudienceChoices(
      screens: screens,
      current: current,
      groupOf: (id) => groups[id] ?? 'general',
      savedName: (id) => {'p3': 'Pulpit tablet'}[id],
    ))
      (o.value, o.label, o.enabled),
  ];

  test('Only connected screens and groups are offered, with counts', () {
    final list = choices([
      (id: 'p1', name: 'Choir phone'),
      (id: 'p2', name: 'Choir tablet'),
      (id: 'web:abc', name: 'Laptop · Chrome (web)'),
    ], 'all');
    expect(list, [
      ('all', 'All connected stage screens · 3', true),
      ('group:choir', 'Choir screens · 2', true),
      ('device:p1', 'Choir phone', true),
      ('device:p2', 'Choir tablet', true),
      ('device:web:abc', 'Laptop · Chrome (web)', true),
    ]);
  });

  test('A chosen screen or group that went away stays, disabled', () {
    expect(choices([(id: 'p1', name: 'Choir phone')], 'device:p3').last, (
      'device:p3',
      'Pulpit tablet · offline',
      false,
    ));
    expect(choices([(id: 'p1', name: 'Choir phone')], 'group:preacher').last, (
      'group:preacher',
      'Preacher screens · none connected',
      false,
    ));
    expect(choices([], 'device:web:zz').last, (
      'device:web:zz',
      'Web screen · offline',
      false,
    ));
  });

  test('With nothing connected, one line says so', () {
    expect(choices([], 'all'), [('all', 'No stage screens connected', false)]);
  });
}
