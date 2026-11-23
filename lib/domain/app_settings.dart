import 'dart:convert';
import 'dart:math' as math;
import 'package:church_service_timer/domain/domain.dart';

const appName = 'Church Service Timer';
const appVersion = '0.36.0 (41)';

/// The privacy policy on the guide website, opened from Settings › About.
const privacyPolicyUrl =
    'https://immanuelokose.github.io/church-service-timer-guide/privacy-policy/';

/// Local interface preferences: never sent to stage peers or restored from a
/// portable backup. Output animation is configured separately.
class AppearancePreferences {
  final String density, dividers, pickerFeedback;

  /// How Live is arranged in a wide window, and whether buttons show their
  /// keyboard key ('automatic' shows them on a computer).
  final String desktopLayout, keyHints;
  final bool highContrast, reducedMotion;
  const AppearancePreferences({
    this.density = 'automatic',
    this.dividers = 'subtle',
    this.pickerFeedback = 'haptics',
    this.highContrast = false,
    this.reducedMotion = false,
    this.desktopLayout = defaultDesktopLayout,
    this.keyHints = 'automatic',
  });
  factory AppearancePreferences.fromJson(Json j) {
    require(
      {
        'compact',
        'comfortable',
        'spacious',
        'automatic',
      }.contains(j['density'] ?? 'automatic'),
      'Unknown layout density.',
    );
    require(
      {'subtle', 'strong', 'hidden'}.contains(j['dividers'] ?? 'subtle'),
      'Unknown divider style.',
    );
    require(
      (j['highContrast'] == null || j['highContrast'] is bool) &&
          (j['reducedMotion'] == null || j['reducedMotion'] is bool),
      'Invalid accessibility preference.',
    );
    require(
      {
        'off',
        'haptics',
        'sound',
        'both',
      }.contains(j['pickerFeedback'] ?? 'haptics'),
      'Unknown picker feedback.',
    );
    require(
      desktopLayoutIds.contains(j['desktopLayout'] ?? defaultDesktopLayout) &&
          keyHintChoices.contains(j['keyHints'] ?? 'automatic'),
      'Unknown desktop layout.',
    );
    return AppearancePreferences(
      density: j['density'] ?? 'automatic',
      dividers: j['dividers'] ?? 'subtle',
      pickerFeedback: j['pickerFeedback'] ?? 'haptics',
      highContrast: j['highContrast'] ?? false,
      reducedMotion: j['reducedMotion'] ?? false,
      desktopLayout: j['desktopLayout'] ?? defaultDesktopLayout,
      keyHints: j['keyHints'] ?? 'automatic',
    );
  }
  AppearancePreferences copyWith({
    String? density,
    String? dividers,
    String? pickerFeedback,
    bool? highContrast,
    bool? reducedMotion,
    String? desktopLayout,
    String? keyHints,
  }) => AppearancePreferences(
    density: density ?? this.density,
    dividers: dividers ?? this.dividers,
    pickerFeedback: pickerFeedback ?? this.pickerFeedback,
    highContrast: highContrast ?? this.highContrast,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    desktopLayout: desktopLayout ?? this.desktopLayout,
    keyHints: keyHints ?? this.keyHints,
  );
  Json toJson() => {
    'density': density,
    'dividers': dividers,
    'pickerFeedback': pickerFeedback,
    'highContrast': highContrast,
    'reducedMotion': reducedMotion,
    'desktopLayout': desktopLayout,
    'keyHints': keyHints,
  };
  @override
  bool operator ==(Object other) =>
      other is AppearancePreferences &&
      density == other.density &&
      dividers == other.dividers &&
      pickerFeedback == other.pickerFeedback &&
      highContrast == other.highContrast &&
      reducedMotion == other.reducedMotion &&
      desktopLayout == other.desktopLayout &&
      keyHints == other.keyHints;
  @override
  int get hashCode => Object.hash(
    density,
    dividers,
    pickerFeedback,
    highContrast,
    reducedMotion,
    desktopLayout,
    keyHints,
  );
}

const themeIds = {
  'midnight_lime',
  'royal_navy',
  'warm_ivory',
  'deep_plum',
  'slate_teal',
  'morning_sky',
  'sage_linen',
  'ocean_deep',
  'cobalt_night',
  'graphite',
  'paper_ink',
  'paper_ink_blue',
  'meadow',
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

/// Size of the church logo, in pixels: square, as the crop makes it.
const churchLogoSize = 256;

/// A church logo: empty, or a square [churchLogoSize] PNG up to 200 kB.
String churchLogoValue(dynamic value) {
  require(value is String, 'Church logo must be image data.');
  final text = value as String;
  if (text.isEmpty) return text;
  require(text.length <= 266668, 'Church logo exceeds 200 kB.');
  try {
    final bytes = base64Decode(text);
    require(
      bytes.length >= 33 && bytes.length <= 200000,
      'Invalid church logo size.',
    );
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    require(
      List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v) &&
          ascii.decode(bytes.sublist(12, 16)) == 'IHDR',
      'Church logo must be a PNG.',
    );
    int uint32(int i) =>
        (bytes[i] << 24) |
        (bytes[i + 1] << 16) |
        (bytes[i + 2] << 8) |
        bytes[i + 3];
    require(
      uint32(16) == churchLogoSize && uint32(20) == churchLogoSize,
      'Church logo must be $churchLogoSize × $churchLogoSize pixels.',
    );
    return text;
  } on RuleError {
    rethrow;
  } catch (_) {
    throw RuleError('Invalid church logo image.');
  }
}

String themeIdValue(dynamic value) {
  require(
    value is String &&
        (themeIds.contains(value) ||
            RegExp(
              r'^custom:[0-9a-f]{6}:[0-9a-f]{6}:[0-9a-f]{6}$',
            ).hasMatch(value)),
    'Unknown appearance theme.',
  );
  if ((value as String).startsWith('custom:')) {
    final parts = value.split(':');
    double luminance(String hex) {
      final rgb = int.parse(hex, radix: 16);
      double channel(int n) {
        final c = n / 255;
        return c <= .04045
            ? c / 12.92
            : math.pow((c + .055) / 1.055, 2.4).toDouble();
      }

      return .2126 * channel((rgb >> 16) & 255) +
          .7152 * channel((rgb >> 8) & 255) +
          .0722 * channel(rgb & 255);
    }

    final bg = luminance(parts[2]), surface = luminance(parts[3]);
    final black = (bg + .05) / .05 >= 1.05 / (bg + .05);
    final ratio = black ? (surface + .05) / .05 : 1.05 / (surface + .05);
    require(
      ratio >= 4.5,
      'Custom background and panel colours need compatible contrast.',
    );
  }
  return value;
}

bool boolSetting(dynamic value) {
  require(value is bool, 'Screen-awake setting must be true or false.');
  return value as bool;
}

/// What the Simulator can stand in for, with the words for each choice.
const simulatorKinds = {'led': 'LED sign', 'stage': 'Stage screen'};

/// The saved Simulator choice; anything else is the LED sign it always
/// was.
String simulatorKindValue(dynamic value) =>
    simulatorKinds.containsKey(value) ? value as String : 'led';

/// The Simulator by the name of what it stands in for, as on its chips.
String simulatorNameOf(String kind) =>
    kind == 'stage' ? 'Stage simulator' : 'LED simulator';

/// Portable saved data only. Active clocks, alarms, hardware and font bytes are
/// deliberately excluded; restoring starts at an idle operator screen.
String exportBackup(
  AppState state,
  Stamp now, {
  Map<String, dynamic>? savedPasswords,
}) {
  final data = state.toJson()
    ..remove('session')
    ..remove('editDrafts')
    ..remove('outputDestination')
    ..remove('version')
    ..remove('appearance')
    ..remove('programLibrary')
    ..remove('lockScreenControls')
    ..remove('dismissedHints')
    ..remove('recentQuickTimers')
    ..remove('autoUpdate')
    ..remove('seenVersion')
    ..remove('settingsLock')
    ..remove('clickerControls')
    ..remove('fullScreenLayout')
    ..remove('simulatorKind')
    ..remove('simulatorLayout')
    ..remove('overtimeAlert')
    ..remove('practisedWall')
    ..remove('practicePrompt')
    ..remove('stageRequests')
    ..remove('programHistory')
    ..remove('programInbox')
    ..remove('segmentLibrary')
    ..remove('recordMetrics')
    ..remove('metricsBatteryBaseline')
    ..remove('importMappings')
    ..remove('webStage')
    ..remove('churchLogo')
    ..remove('savedLooks');
  // The logo only when one is set, so plain backups stay readable by
  // earlier versions.
  if (state.churchLogo.isNotEmpty) data['churchLogo'] = state.churchLogo;
  if (state.savedLooks.isNotEmpty)
    data['savedLooks'] = [for (final l in state.savedLooks) l.toJson()];
  if (state.segmentLibrary.isNotEmpty)
    data['segmentLibrary'] = [for (final s in state.segmentLibrary) s.toJson()];
  // Earlier program versions, keyed by name because IDs stay on the phone.
  final history = <String, dynamic>{
    for (final t in state.templates)
      if (state.versionsOf(t.id).isNotEmpty)
        t.name: [for (final v in state.versionsOf(t.id)) v.toJson()],
  };
  if (history.isNotEmpty) data['programHistory'] = history;
  // Program IDs stay on this phone; a restore assigns them afresh.
  data['templates'] = [
    for (final t in data['templates'] as List) portableProgram(t as Json),
  ];
  data['reports'] = [
    for (final r in data['reports'] as List)
      if ((r as Json)['program'] is Json)
        {...r, 'program': portableProgram(r['program'] as Json)}
      else
        r,
  ];
  final result = const JsonEncoder.withIndent('  ').convert({
    'type': 'church-service-timer-backup',
    // Version 11 only with saved looks, 10 only with a church logo, 9 only with program history or a
    // segment library, 8 only with sealed passwords, so plain backups
    // remain readable by earlier versions.
    'schemaVersion': state.savedLooks.isNotEmpty
        ? 11
        : state.churchLogo.isNotEmpty
        ? 10
        : history.isNotEmpty || state.segmentLibrary.isNotEmpty
        ? 9
        : savedPasswords == null
        ? 7
        : 8,
    'createdUtc': DateTime.fromMillisecondsSinceEpoch(
      now.wall,
      isUtc: true,
    ).toIso8601String(),
    'data': data,
    'savedPasswords': ?savedPasswords,
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
    keys(envelope, {
      'type',
      'schemaVersion',
      'createdUtc',
      'data',
      if (envelope['schemaVersion'] >= 8) 'savedPasswords',
    }, 'Backup');
    require(
      envelope['type'] == 'church-service-timer-backup' &&
          {
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
          }.contains(envelope['schemaVersion']),
      'Choose a supported Church Service Timer backup.',
    );
    final data = Map<String, dynamic>.from(envelope['data']);
    keys(data, {
      'templates',
      if (envelope['schemaVersion'] >= 6) 'clockFormat',
      if (envelope['schemaVersion'] >= 7) 'clockBlink',
      if (envelope['schemaVersion'] >= 5) 'notificationClearSeconds',
      if (envelope['schemaVersion'] >= 5) 'printPreferences',
      'defaults',
      'reports',
      'stageCues',
      if (envelope['schemaVersion'] >= 4) 'quickMessages',
      'pixelShape',
      'groupTemplates',
      'churchName',
      'themeId',
      'keepScreenAwake',
      if (envelope['schemaVersion'] >= 2) 'churchBanner',
      if (envelope['schemaVersion'] >= 9) 'programHistory',
      if (envelope['schemaVersion'] >= 9) 'segmentLibrary',
      if (envelope['schemaVersion'] >= 10) 'churchLogo',
      if (envelope['schemaVersion'] >= 11) 'savedLooks',
    }, 'Backup data');
    final history = data.remove('programHistory');
    final logo = churchLogoValue(data.remove('churchLogo') ?? '');
    final segments = readSegmentLibrary(data.remove('segmentLibrary'));
    final looks = readSavedLooks(data.remove('savedLooks'));
    require(
      data.length ==
              (envelope['schemaVersion'] >= 7
                  ? 15
                  : envelope['schemaVersion'] >= 6
                  ? 14
                  : envelope['schemaVersion'] >= 5
                  ? 13
                  : envelope['schemaVersion'] >= 4
                  ? 11
                  : envelope['schemaVersion'] >= 2
                  ? 10
                  : 9) &&
          data.values.every((v) => v != null),
      'Backup is missing saved preferences.',
    );
    require(
      data['templates'] is List &&
          data['reports'] is List &&
          data['stageCues'] is List,
      'Backup is missing programs, reports or cues.',
    );
    final versions = readProgramHistory(history);
    final restored = AppState.fromJson({
      ...data,
      'version': envelope['schemaVersion'] >= 7
          ? 13
          : envelope['schemaVersion'] >= 6
          ? 12
          : envelope['schemaVersion'] >= 5
          ? 11
          : envelope['schemaVersion'] >= 4
          ? 10
          : envelope['schemaVersion'] == 3
          ? 9
          : 8,
      'session': Session(id: 'restored', anchor: now, held: true).toJson(),
    });
    restored.segmentLibrary = segments;
    restored.churchLogo = logo;
    restored.savedLooks = looks;
    for (final e in versions.entries) {
      final program = restored.templates.where((t) => t.name == e.key);
      require(program.isNotEmpty, 'Backup history names a missing program.');
      restored.programHistory[program.single.id] = e.value;
    }
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

/// The sealed saved-password block of a backup, or null when it has none.
Map<String, dynamic>? backupSavedPasswords(String raw) {
  final envelope = jsonDecode(raw);
  if (envelope is! Map || envelope['savedPasswords'] is! Map) return null;
  return Map<String, dynamic>.from(envelope['savedPasswords']);
}
