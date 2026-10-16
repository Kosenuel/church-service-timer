import 'package:flutter/services.dart';

import 'domain.dart';

abstract class DevicePort {
  Future<Stamp> clock();
  Future<String?> load();
  Future<void> save(String state);
  Future<Map<String, dynamic>?> pickFile();
  Future<void> exportFile(String filename, String content);
}

class AndroidPort implements DevicePort {
  static const channel = MethodChannel('church.timer/device');
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
