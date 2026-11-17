import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';

/// One IPv4 address of this computer and the adapter it belongs to.
typedef LanAddress = ({String adapter, String address});

final _virtualAdapter = RegExp(
  r'vethernet|virtual|vmware|vbox|hyper-v|wsl|loopback|bluetooth|tailscale|zerotier|wireguard|vpn|tap-|docker|tunnel',
  caseSensitive: false,
);
final _wifiAdapter = RegExp(r'wi-?fi|wlan|wireless', caseSensitive: false);

bool _private(String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// Chooses the address other devices should use to reach this computer.
///
/// A PC can be on several networks at once: Ethernet to the church
/// network, Wi-Fi to the LED sign, plus adapters that only exist for
/// virtual machines or a VPN. Phones cannot reach the last kind, and the
/// sign's own network ([avoid]) is the wrong place to send them when there
/// is another. Among what is left, a wired connection comes before Wi-Fi
/// (when a PC has both, the Wi-Fi is usually the one borrowed for the
/// sign), and the order is otherwise kept stable so the shared link does
/// not flip between two equally good addresses.
String? pickLanAddress(List<LanAddress> candidates, {String? avoid}) {
  final usable = candidates.where((c) => _private(c.address)).toList();
  if (usable.isEmpty) return null;
  int rank(LanAddress c) =>
      (_virtualAdapter.hasMatch(c.adapter) ? 4 : 0) +
      (c.address == avoid ? 2 : 0) +
      (_wifiAdapter.hasMatch(c.adapter) ? 1 : 0);
  final ranked = [...usable]
    ..sort((x, y) {
      final byRank = rank(x).compareTo(rank(y));
      return byRank != 0 ? byRank : x.address.compareTo(y.address);
    });
  return ranked.first.address;
}

Future<List<LanAddress>> lanAddresses() async => [
  for (final interface in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  ))
    for (final address in interface.addresses)
      (adapter: interface.name, address: address.address),
];

/// The Wi-Fi network name from `netsh wlan show interfaces`, or '' when
/// not on Wi-Fi. The "SSID" label is the same in every Windows language;
/// the "BSSID" line just below it must not be mistaken for it.
String parseNetshSsid(String output) {
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^\s*SSID\s*:\s?(.*)$').firstMatch(line);
    if (match != null) return match.group(1)!.trimRight();
  }
  return '';
}

/// Whether this computer is on a network at all, and its Wi-Fi name when
/// Windows will say (it needs Location turned on in recent versions).
Future<Json> desktopNetworkInfo() async {
  var connected = false;
  try {
    connected = (await lanAddresses()).isNotEmpty;
  } catch (_) {}
  var ssid = '';
  try {
    final result = await Process.run('netsh', [
      'wlan',
      'show',
      'interfaces',
    ]).timeout(const Duration(seconds: 4));
    if (result.exitCode == 0) ssid = parseNetshSsid('${result.stdout}');
  } catch (_) {
    // No Wi-Fi adapter, or Windows would not say: the name stays empty.
  }
  return {'wifiConnected': connected, 'ssid': ssid};
}
