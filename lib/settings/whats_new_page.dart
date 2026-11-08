import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:church_service_timer/shared/app_theme.dart';

/// One release from CHANGELOG.md: its heading and plain-text entries.
class ReleaseNotes {
  final String heading;
  final List<String> entries;
  const ReleaseNotes(this.heading, this.entries);
}

/// Reads the bundled changelog's "## …" sections and their "- " entries.
/// Nested items are folded into their parent; Markdown emphasis is dropped.
List<ReleaseNotes> parseChangelog(String text) {
  final releases = <ReleaseNotes>[];
  String? heading;
  var entries = <String>[];
  String clean(String s) => s
      .replaceAll(RegExp(r'\*\*|`'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      // The bundled Roboto has no → or ✕; use characters it has.
      .replaceAll('→', '›')
      .replaceAll('✕', '×')
      // "7/November/2026" reads as "7 November 2026".
      .replaceAllMapped(
        RegExp(r'\b(\d{1,2})/([A-Z][a-z]+)/(\d{4})\b'),
        (m) => '${m[1]} ${m[2]} ${m[3]}',
      );
  void close() {
    if (heading != null && entries.isNotEmpty)
      releases.add(ReleaseNotes(heading, List.unmodifiable(entries)));
  }

  for (final line in text.split('\n')) {
    if (line.startsWith('## ')) {
      close();
      heading = clean(line.substring(3).trim());
      entries = [];
    } else if (heading != null && line.startsWith('- ')) {
      entries.add(clean(line.substring(2).trim()));
    } else if (heading != null &&
        line.startsWith('  - ') &&
        entries.isNotEmpty) {
      entries[entries.length - 1] =
          '${entries.last} ${clean(line.trim().substring(2))}';
    }
  }
  close();
  return releases;
}

class WhatsNewPage extends StatelessWidget {
  final Future<String> Function() load;
  const WhatsNewPage({super.key, this.load = _bundled});
  static Future<String> _bundled() => rootBundle.loadString('CHANGELOG.md');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What’s new')),
    body: FutureBuilder<String>(
      future: load(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(child: Text('Release notes are unavailable.'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final releases = parseChangelog(snapshot.data!);
        final colors = appColors(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            for (final release in releases) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  release.heading,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: release == releases.first ? colors.accent : null,
                  ),
                ),
              ),
              for (final entry in release.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 10),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: colors.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(child: Text(entry)),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}
