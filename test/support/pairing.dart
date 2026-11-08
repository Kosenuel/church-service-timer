import 'package:church_service_timer/pairing/pairing.dart';

import 'waiting.dart';

class PairMemoryStore {
  String? value;
  bool fail = false;
  PairHub hub() => PairHub()
    ..readMemory = (() async => value)
    ..writeMemory = ((next) async {
      if (fail) throw StateError('Disk full');
      value = next;
    });
}

Future<String> pair(
  PairHub host,
  PairHub client, {
  String role = 'stage',
}) async {
  await client.join(host.code!.encode(), 'Stage tablet', role);
  await eventually(() => host.peers.isNotEmpty);
  final peer = host.peers.last;
  await host.approve(peer);
  await eventually(() => !client.stale);
  return peer.id;
}
