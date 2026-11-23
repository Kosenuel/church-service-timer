import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';
import '../domain/feature_cases.dart' show epoch, equal, rejects;
import '../support/stock_end_screen.dart';

final revision06Cases = <String, void Function()>{
  'Legacy state and templates migrate without losing display settings': () {
    final old = stockEndState(epoch).toJson()..['version'] = 5;
    old.remove('groupTemplates');
    for (final t in old['templates'] as List) {
      t['schemaVersion'] = 2;
      t.remove('type');
    }
    final a = AppState.fromJson(old);
    equal(a.groupTemplates, true);
    equal(a.templates.first.type, 'service');
    equal(a.templates.last.type, 'rehearsal');
    equal(a.templates.first.display.end!.bold, true);
    equal(a.toJson()['version'], 16);
  },
  'Template group and list preference survive restart and JSON import': () {
    final a = AppState.fresh(epoch)..groupTemplates = true;
    final restored = AppState.fromJson(
      jsonDecode(jsonEncode(a.toJson())) as Json,
    );
    equal(restored.groupTemplates, true);
    final imported = importTemplate(
      exportJson(restored.templates.last),
      'service.json',
      DisplaySettings(),
    );
    equal(imported.type, 'rehearsal');
    equal(imported.toJson()['schemaVersion'], 4);
    equal(imported.renamed('Practice').type, 'rehearsal');
  },
  'Shared zero and settings changes preserve explicit template group': () {
    final a = AppState.fresh(epoch);
    a.defaults = a.defaults.withZero(const TextLayout('STOP'));
    a.applySharedZero();
    final t = a.templates.last.withDisplay(
      a.templates.last.display.withEnd(const TextLayout('AMEN')),
    );
    equal(t.type, 'rehearsal');
    equal(t.display.zero!.text, 'STOP');
  },
  'Duplicate preserves every setting and generates unique bounded names': () {
    final a = AppState.fresh(epoch);
    final original = a.templates.last;
    final first = a.duplicateTemplate(original);
    final second = a.duplicateTemplate(original);
    equal(first.name, 'Quick rehearsal (copy)');
    equal(second.name, 'Quick rehearsal (copy 2)');
    equal(first.type, original.type);
    equal(
      jsonEncode(first.display.toJson()),
      jsonEncode(original.display.toJson()),
    );
    equal(first.segments.length, original.segments.length);
    a.saveTemplate(original.renamed('A' * 80).withId(''));
    final longCopy = a.duplicateTemplate(a.templates.last);
    equal(first.id == original.id, false);
    equal(longCopy.name.runes.length, 80);
    equal(longCopy.name.endsWith(' (copy)'), true);
  },
  'Deleting a template leaves the running snapshot intact': () {
    final a = AppState.fresh(epoch);
    final original = a.templates.last;
    a.session = transition(a.session, 'load', epoch, value: original);
    a.session = transition(a.session, 'start', epoch);
    a.deleteTemplate(original);
    equal(a.templates.length, 1);
    equal(a.session.timeline!.name, original.name);
    equal(a.session.phase, 'active');
  },
  'Stale template references cannot delete or duplicate replacements': () {
    final a = AppState.fresh(epoch);
    final original = a.templates.first;
    a.templates[0] = original.withDisplay(
      original.display.withEnd(const TextLayout('AMEN')),
    );
    rejects(() => a.deleteTemplate(original));
    rejects(() => a.duplicateTemplate(original));
    equal(a.templates.length, 2);
    equal(a.templates.first.display.end!.text, 'AMEN');
  },
  'Invalid template groups and unsupported versions are rejected': () {
    final t = AppState.fresh(epoch).templates.first.toJson();
    t['type'] = 'anything';
    rejects(() => Timeline.fromJson(t));
    t.remove('type');
    rejects(() => Timeline.fromJson(t));
    t['type'] = 'service';
    t['schemaVersion'] = 99;
    rejects(() => Timeline.fromJson(t));
    final a = AppState.fresh(epoch).toJson()..['groupTemplates'] = 'yes';
    rejects(() => AppState.fromJson(a));
  },
};
