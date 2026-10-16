part of 'domain.dart';

const appName = 'Church Service Timer';
const appVersion = '0.9.0 (9)';
const themeIds = {
  'midnight_lime',
  'royal_navy',
  'warm_ivory',
  'deep_plum',
  'slate_teal',
};
const backupLimitBytes = 16 * 1024 * 1024;

String churchNameValue(dynamic value) {
  require(value is String, 'Church name must be text.');
  final name = (value as String).trim();
  require(
    name.runes.length <= 80 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name),
    'Church name must be one line, up to 80 characters.',
  );
  return name;
}

/// Stored banners are normalized, metadata-free PNGs, never the original photo.
String churchBannerValue(dynamic value) {
  require(value is String, 'Church banner must be image data.');
  final text = value as String;
  if (text.isEmpty) return text;
  require(text.length <= 666668, 'Church banner exceeds 500 kB.');
  try {
    final bytes = base64Decode(text);
    require(
      bytes.length >= 33 && bytes.length <= 500000,
      'Invalid church banner size.',
    );
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    require(
      List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v) &&
          ascii.decode(bytes.sublist(12, 16)) == 'IHDR',
      'Church banner must be a PNG.',
    );
    int uint32(int i) =>
        (bytes[i] << 24) |
        (bytes[i + 1] << 16) |
        (bytes[i + 2] << 8) |
        bytes[i + 3];
    require(
      uint32(16) == 600 && uint32(20) == 200,
      'Church banner must be 600 × 200 pixels.',
    );
    return text;
  } on RuleError {
    rethrow;
  } catch (_) {
    throw RuleError('Invalid church banner image.');
  }
}

String themeIdValue(dynamic value) {
  require(themeIds.contains(value), 'Unknown appearance theme.');
  return value as String;
}

bool boolSetting(dynamic value) {
  require(value is bool, 'Screen-awake setting must be true or false.');
  return value as bool;
}

/// Portable saved data only. Active clocks, alarms, hardware and font bytes are
/// deliberately excluded; restoring starts at an idle operator screen.
String exportBackup(AppState state, Stamp now) {
  final data = state.toJson()
    ..remove('session')
    ..remove('version');
  final result = const JsonEncoder.withIndent('  ').convert({
    'type': 'church-service-timer-backup',
    'schemaVersion': 2,
    'createdUtc': DateTime.fromMillisecondsSinceEpoch(
      now.wall,
      isUtc: true,
    ).toIso8601String(),
    'data': data,
  });
  require(
    utf8.encode(result).length <= backupLimitBytes,
    'Backup exceeds 16 MiB. Export older reports separately and clear them before creating this backup.',
  );
  return result;
}

AppState importBackup(String raw, Stamp now) {
  require(
    utf8.encode(raw).length <= backupLimitBytes,
    'Backup exceeds 16 MiB.',
  );
  try {
    final envelope = Map<String, dynamic>.from(jsonDecode(raw));
    keys(envelope, {'type', 'schemaVersion', 'createdUtc', 'data'}, 'Backup');
    require(
      envelope['type'] == 'church-service-timer-backup' &&
          {1, 2}.contains(envelope['schemaVersion']),
      'Choose a supported Church Service Timer backup.',
    );
    final data = Map<String, dynamic>.from(envelope['data']);
    keys(data, {
      'templates',
      'defaults',
      'reports',
      'stageCues',
      'pixelShape',
      'groupTemplates',
      'churchName',
      'themeId',
      'keepScreenAwake',
      if (envelope['schemaVersion'] == 2) 'churchBanner',
    }, 'Backup data');
    require(
      data.length == (envelope['schemaVersion'] == 2 ? 10 : 9) &&
          data.values.every((v) => v != null),
      'Backup is missing saved preferences.',
    );
    require(
      data['templates'] is List &&
          data['reports'] is List &&
          data['stageCues'] is List,
      'Backup is missing templates, reports or cues.',
    );
    final restored = AppState.fromJson({
      ...data,
      'version': 8,
      'session': Session(id: 'restored', anchor: now, held: true).toJson(),
    });
    require(
      restored.reports.map((r) => r.id).toSet().length ==
          restored.reports.length,
      'Backup contains duplicate report records.',
    );
    for (final r in restored.reports) {
      require(
        r.id.isNotEmpty &&
            r.name.isNotEmpty &&
            r.endedWall >= 0 &&
            r.endedWall <= 8640000000000000 &&
            (r.startedWall == null ||
                (r.startedWall! >= 0 && r.startedWall! <= 8640000000000000)) &&
            (r.totalMs == null || r.totalMs! >= 0) &&
            {1, 5, 10, 30, 60}.contains(r.rate),
        'Backup contains an invalid report.',
      );
      for (final row in r.rows) {
        require(
          row.name.isNotEmpty &&
              row.plannedMs > 0 &&
              row.pausedMs >= 0 &&
              (row.actualMs == null || row.actualMs! >= 0),
          'Backup contains invalid segment timing.',
        );
      }
    }
    return restored;
  } on RuleError {
    rethrow;
  } catch (_) {
    throw RuleError(
      'This backup is incomplete or invalid. No data was changed.',
    );
  }
}
