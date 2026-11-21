import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';

/// Drafts are local, bounded and never included in portable backups or pairing.
Map<String, Json> readEditDrafts(dynamic value) {
  if (value == null) return {};
  require(value is Map && value.length <= 50, 'Invalid saved drafts.');
  require(
    utf8.encode(jsonEncode(value)).length <= 2 * 1024 * 1024,
    'Saved drafts exceed 2 MiB.',
  );
  return {
    for (final e in (value as Map).entries)
      e.key as String: Map<String, dynamic>.from(e.value),
  };
}

/// Does not parse the whole program: drafts can have an empty name or rundown.
Timeline programFromDraft(Json raw, DisplaySettings defaults) => Timeline(
  raw['name'] as String,
  (raw['segments'] as List)
      .map((v) => Segment.fromJson(Map<String, dynamic>.from(v)))
      .toList(),
  // A draft's end screen is null when the program has none.
  defaults.withEnd(
    raw['end'] == null
        ? null
        : TextLayout.fromJson(Map<String, dynamic>.from(raw['end'])),
  ),
  type: raw['type'] as String,
);

QuickMessage messageFromDraft(Json j) => QuickMessage(
  headline: j['headline'] as String? ?? '',
  body: j['body'] as String? ?? '',
  bold: j['bold'] == true,
  italic: j['italic'] == true,
  requestSeen: j['requestSeen'] == true,
  align: j['align'] as String? ?? 'center',
  palette: j['palette'] as String? ?? 'white',
  seconds: j['seconds'] as int? ?? 10,
  scale: (j['scale'] as num? ?? 1).toDouble(),
);
