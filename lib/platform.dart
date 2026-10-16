import 'package:flutter/services.dart';

import 'domain.dart';

abstract class DevicePort {
  Future<String?> pickChurchBanner() async => null;
  Future<String> installedVersion() async => appVersion;
  Future<void> setKeepScreenAwake(bool enabled) async {}
  Future<Map<String, dynamic>?> pickBackup() => pickFile();
  Future<bool> hasTimesFont() async => false;
  Future<bool> importTimesFont() async => false;
  Future<Json> rasterizeTimes(TextLayout layout) async =>
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
  static const channel = MethodChannel('church.timer/device');
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
  Future<bool> hasTimesFont() async =>
      await channel.invokeMethod<bool>('hasTimesFont') ?? false;
  @override
  Future<bool> importTimesFont() async =>
      await channel.invokeMethod<bool>('importTimesFont') ?? false;
  @override
  Future<Json> rasterizeTimes(TextLayout layout) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMethod<Map>('rasterizeTimes', layout.toJson()))!,
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
