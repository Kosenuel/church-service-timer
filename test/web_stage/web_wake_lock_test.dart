import 'dart:io';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the page's own wake-lock code in node against a fake browser.
Future<String> run(String scenario) async {
  final from = webStagePage.indexOf('let wake = null;');
  final to = webStagePage.indexOf('function stop()');
  final code = webStagePage.substring(from, to);
  final script =
      '''
let role = null, lastState = null, visible = 'visible', held = 0, requests = 0, refuse = false;
const listeners = [];
const document = { get visibilityState() { return visible; }, addEventListener: (n, f) => listeners.push(f) };
const navigator = { wakeLock: { request: async () => {
  requests++;
  if (refuse) throw new Error('refused');
  held++;
  return { release: async () => { held--; }, addEventListener() {} };
} } };
$code
const tick = () => new Promise((r) => setTimeout(r, 0));
(async () => {
$scenario
})();
''';
  final result = await Process.run('node', ['-e', script]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return '${result.stdout}'.trim();
}

void main() {
  final hasNode = Process.runSync('node', ['--version']).exitCode == 0;

  test('the page holds the wake lock only for a stage screen or a running '
      'service', () async {
    expect(
      await run('''
const log = [];
role = 'overview'; lastState = { phase: 'idle' }; syncAwake(); await tick(); log.push(held);
lastState = { phase: 'ready' }; syncAwake(); await tick(); log.push(held);
lastState = { phase: 'active' }; syncAwake(); await tick(); log.push(held);
syncAwake(); await tick(); log.push(held);
lastState = { phase: 'ended' }; syncAwake(); await tick(); log.push(held);
role = 'stage'; lastState = { phase: 'idle' }; syncAwake(); await tick(); log.push(held);
role = 'order'; lastState = { phase: 'active' }; syncAwake(); await tick(); log.push(held);
role = 'overview'; syncAwake(); await tick();
visible = 'hidden'; syncAwake(); await tick(); log.push(held);
visible = 'visible'; syncAwake(); await tick(); log.push(held);
console.log(log.join(','));
'''),
      '0,0,1,1,0,1,0,0,1',
    );
  }, skip: hasNode ? false : 'node is not installed');

  test('a refused lock is quiet and tried again on the next change', () async {
    expect(
      await run('''
role = 'stage'; refuse = true; syncAwake(); await tick();
refuse = false; syncAwake(); await tick();
console.log(requests + ',' + held);
'''),
      '2,1',
    );
  }, skip: hasNode ? false : 'node is not installed');

  test('a lock that arrives after the service ended is let go', () async {
    expect(
      await run('''
role = 'overview'; lastState = { phase: 'active' }; syncAwake();
lastState = { phase: 'ended' }; syncAwake();
await tick(); await tick();
console.log(held);
'''),
      '0',
    );
  }, skip: hasNode ? false : 'node is not installed');
}
