import 'package:flutter/services.dart';
import 'dart:convert';

import 'domain.dart';
import 'package:nsd/nsd.dart' as nsd;

abstract class DevicePort {
  Future<String?> loadPairing() async => null;
  Future<void> savePairing(String value) async {}
  Future<List<Json>> discoverPairHosts() async => [];
  Future<void> setDisplayAutoReconnect(bool enabled) async {}
  Future<Json> displayNetworkInfo({bool requestName = false}) async => {};
  Future<void> advertisePairHost(int port, {String? hostId}) async {}
  Future<void> stopPairAdvertisement() async {}
  Future<Json> administerDisplay(
    String kind,
    String value,
    int generation,
  ) async => throw RuleError('Device administration requires Android.');
  Future<void> printServiceSheet(String name, String html) async =>
      throw RuleError('Printing requires Android.');
  Future<String> localNetworkAddress() async => '127.0.0.1';
  Future<void> saveDisplayPassword(String id, String password) async {}
  Future<String?> savedDisplayPassword(String id) async => null;
  Future<void> forgetDisplayPassword(String id) async {}
  Future<void> forgetDisplay() async {}

  void setBackgroundHandler(Future<void> Function()? handler) {}
  Future<bool> setActiveService(bool enabled) async => false;
  Future<bool> activeServiceRunning() async => false;
  Future<Json> displayPreferences() async => {'hardware': false};
  Future<List<Json>> discoverDisplays() async =>
      throw RuleError('Android Wi-Fi is required.');
  Future<Json> connectDisplay(String id, String password) async =>
      throw RuleError('Android Wi-Fi is required.');
  Future<void> disconnectDisplay() async {}
  Future<void> useSimulator() async {}
  Future<void> openWifiSettings() async {}
  Future<Json> checkDisplay() async => {'connected': false};
  Future<Json> sendDisplay(
    Uint8List bytes,
    int generation,
    int? deadline,
  ) async => throw RuleError('Android Wi-Fi is required.');
  Future<bool> composeFeedback(String subject, String body) async => false;
  Future<String?> pickChurchBanner() async => null;
  Future<String> installedVersion() async => appVersion;
  Future<void> setKeepScreenAwake(bool enabled) async {}
  Future<Map<String, dynamic>?> pickBackup() => pickFile();
  Future<bool> hasTinosFont() async => false;
  Future<Json> rasterizeTinos(TextLayout layout) async =>
      throw RuleError('Native font rendering requires Android.');
  Future<Json> notificationStatus() async => {
    'enabled': false,
    'exact': false,
    'sound': false,
  };
  Future<void> enableNotifications() async {}
  Future<void> openNotificationSettings() async {}
  Future<void> requestExactWarnings() async {}
  Future<void> syncWarnings(Json plan) async {}
  Future<void> testNotification() async {}
  Future<Stamp> clock();
  Future<String?> load();
  Future<void> save(String state);
  Future<Map<String, dynamic>?> pickFile();
  Future<void> exportFile(String filename, String content);
}

class AndroidPort extends DevicePort {
  @override
  Future<String?> loadPairing() => channel.invokeMethod<String>('loadPairing');
  @override
  Future<void> savePairing(String value) =>
      channel.invokeMethod<void>('savePairing', value);
  @override
  Future<List<Json>> discoverPairHosts() async {
    final discovery = await nsd.startDiscovery(
      '_cstimer._tcp',
      ipLookupType: nsd.IpLookupType.v4,
    );
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      return [
        for (final service in discovery.services)
          if (service.port != null && service.txt?['id'] != null)
            for (final address in service.addresses ?? [])
              {
                'id': utf8.decode(service.txt!['id']!),
                'address': address.address,
                'port': service.port,
              },
      ];
    } finally {
      await nsd.stopDiscovery(discovery);
    }
  }

  @override
  Future<void> setDisplayAutoReconnect(bool enabled) =>
      channel.invokeMethod<void>('w2AutoReconnect', enabled);
  @override
  Future<Json> displayNetworkInfo({bool requestName = false}) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMethod<Map>('w2NetworkInfo', requestName)) ?? {},
      );
  nsd.Registration? _pairRegistration;
  int _pairAdvertisementGeneration = 0;
  @override
  Future<void> advertisePairHost(int port, {String? hostId}) async {
    await stopPairAdvertisement();
    final generation = _pairAdvertisementGeneration;
    final registration = await nsd.register(
      nsd.Service(
        name: 'Church Service Timer',
        type: '_cstimer._tcp',
        port: port,
        txt: hostId == null
            ? null
            : {'id': Uint8List.fromList(utf8.encode(hostId))},
      ),
    );
    if (generation != _pairAdvertisementGeneration) {
      await nsd.unregister(registration);
    } else {
      _pairRegistration = registration;
    }
  }

  @override
  Future<void> stopPairAdvertisement() async {
    _pairAdvertisementGeneration++;
    final registration = _pairRegistration;
    _pairRegistration = null;
    if (registration != null) await nsd.unregister(registration);
  }

  static const channel = MethodChannel('church.timer/device');
  @override
  Future<Json> administerDisplay(
    String kind,
    String value,
    int generation,
  ) async => Map<String, dynamic>.from(
    (await channel.invokeMethod<Map>('w2Admin', {
      'kind': kind,
      'value': value,
      'generation': generation,
    }))!,
  );
  @override
  Future<void> printServiceSheet(String name, String html) =>
      channel.invokeMethod<void>('printSheet', {'name': name, 'html': html});
  @override
  Future<String> localNetworkAddress() async =>
      (await channel.invokeMethod<String>('localAddress'))!;
  @override
  Future<void> saveDisplayPassword(String id, String password) =>
      channel.invokeMethod<void>('saveDisplayPassword', {
        'id': id,
        'password': password,
      });
  @override
  Future<String?> savedDisplayPassword(String id) =>
      channel.invokeMethod<String>('savedDisplayPassword', id);
  @override
  Future<void> forgetDisplayPassword(String id) =>
      channel.invokeMethod<void>('forgetDisplayPassword', id);
  @override
  Future<void> forgetDisplay() => channel.invokeMethod<void>('forgetDisplay');

  @override
  void setBackgroundHandler(Future<void> Function()? handler) {
    channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'backgroundTick') await handler();
            },
    );
  }

  @override
  Future<bool> setActiveService(bool enabled) async =>
      await channel.invokeMethod<bool>('activeService', enabled) ?? false;
  @override
  Future<bool> activeServiceRunning() async =>
      await channel.invokeMethod<bool>('activeServiceRunning') ?? false;
  @override
  Future<Json> displayPreferences() async => Map<String, dynamic>.from(
    (await channel.invokeMethod<Map>('w2Preferences'))!,
  );
  @override
  Future<List<Json>> discoverDisplays() async =>
      (await channel.invokeMethod<List>(
        'w2Discover',
      ))!.map((v) => Map<String, dynamic>.from(v)).toList();
  @override
  Future<Json> connectDisplay(String id, String password) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMethod<Map>('w2Connect', {
          'id': id,
          'password': password,
        }))!,
      );
  @override
  Future<void> disconnectDisplay() =>
      channel.invokeMethod<void>('w2Disconnect');
  @override
  Future<void> useSimulator() => channel.invokeMethod<void>('w2Simulator');
  @override
  Future<void> openWifiSettings() => channel.invokeMethod<void>('wifiSettings');
  @override
  Future<Json> checkDisplay() async =>
      Map<String, dynamic>.from((await channel.invokeMethod<Map>('w2Status'))!);
  @override
  Future<Json> sendDisplay(
    Uint8List bytes,
    int generation,
    int? deadline,
  ) async => Map<String, dynamic>.from(
    (await channel.invokeMethod<Map>('w2Send', {
      'bytes': bytes,
      'generation': generation,
      'deadline': deadline,
    }))!,
  );
  @override
  Future<bool> composeFeedback(String subject, String body) async =>
      await channel.invokeMethod<bool>('composeFeedback', {
        'subject': subject,
        'body': body,
      }) ??
      false;
  @override
  Future<String?> pickChurchBanner() =>
      channel.invokeMethod<String>('pickChurchBanner');
  @override
  Future<String> installedVersion() async =>
      await channel.invokeMethod<String>('appVersion') ?? appVersion;
  @override
  Future<void> setKeepScreenAwake(bool enabled) =>
      channel.invokeMethod<void>('keepScreenAwake', enabled);
  @override
  Future<Map<String, dynamic>?> pickBackup() async {
    final result = await channel.invokeMethod<Map>('pick', {
      'maxBytes': backupLimitBytes,
    });
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  @override
  Future<bool> hasTinosFont() async =>
      await channel.invokeMethod<bool>('hasTinosFont') ?? false;
  @override
  Future<Json> rasterizeTinos(TextLayout layout) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMethod<Map>('rasterizeTinos', layout.toJson()))!,
      );
  @override
  Future<Json> notificationStatus() async => Map<String, dynamic>.from(
    (await channel.invokeMethod<Map>('notificationStatus'))!,
  );
  @override
  Future<void> enableNotifications() =>
      channel.invokeMethod<void>('enableNotifications');
  @override
  Future<void> openNotificationSettings() =>
      channel.invokeMethod<void>('notificationSettings');
  @override
  Future<void> requestExactWarnings() =>
      channel.invokeMethod<void>('exactWarnings');
  @override
  Future<void> syncWarnings(Json plan) =>
      channel.invokeMethod<void>('syncWarnings', plan);
  @override
  Future<void> testNotification() =>
      channel.invokeMethod<void>('testNotification');
  @override
  Future<Stamp> clock() async => Stamp.fromJson(
    Map<String, dynamic>.from((await channel.invokeMethod('clock')) as Map),
  );
  @override
  Future<String?> load() => channel.invokeMethod<String>('load');
  @override
  Future<void> save(String state) => channel.invokeMethod<void>('save', state);
  @override
  Future<Map<String, dynamic>?> pickFile() async {
    final result = await channel.invokeMethod<Map>('pick');
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  @override
  Future<void> exportFile(String filename, String content) => channel
      .invokeMethod<void>('export', {'name': filename, 'content': content});
}
