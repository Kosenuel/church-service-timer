import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:church_service_timer/shared/app_theme.dart';

/// One release from CHANGELOG.md: its heading and plain-text entries.
/// [leads] holds each entry's bold lead-in ("Guided practice."), or '' when
/// the entry has none, so the page can show it in bold.
class ReleaseNotes {
  final String heading;
  final List<String> entries;
  final List<String> leads;
  const ReleaseNotes(this.heading, this.entries, [this.leads = const []]);
  String lead(int i) => i < leads.length ? leads[i] : '';
}

/// Reads the bundled changelog's "## …" sections and their "- " entries.
/// Nested items are folded into their parent; Markdown emphasis is dropped.
List<ReleaseNotes> parseChangelog(String text) {
  final releases = <ReleaseNotes>[];
  String? heading;
  var entries = <String>[];
  var leads = <String>[];
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
      releases.add(
        ReleaseNotes(
          heading,
          List.unmodifiable(entries),
          List.unmodifiable(leads),
        ),
      );
  }

  for (final line in text.split('\n')) {
    if (line.startsWith('## ')) {
      close();
      heading = clean(line.substring(3).trim());
      entries = [];
      leads = [];
    } else if (heading != null && line.startsWith('- ')) {
      final raw = line.substring(2).trim();
      final lead = RegExp(r'^\*\*(.+?)\*\*').firstMatch(raw);
      entries.add(clean(raw));
      leads.add(lead == null ? '' : clean(lead[1]!));
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
        Widget entries(ReleaseNotes release) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, entry) in release.entries.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
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
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (release.lead(i).isNotEmpty &&
                                entry.startsWith(release.lead(i))) ...[
                              TextSpan(
                                text: release.lead(i),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: entry.substring(release.lead(i).length),
                              ),
                            ] else
                              TextSpan(text: entry),
                          ],
                        ),
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        final heading = Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
        // The two newest releases are open; older ones fold away so the page
        // is not one long wall of text.
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final (i, release) in releases.indexed)
              Card(
                margin: const EdgeInsets.only(top: 12),
                clipBehavior: Clip.antiAlias,
                child: i < 2
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              release.heading,
                              style: heading?.copyWith(
                                color: i == 0 ? colors.accent : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            entries(release),
                          ],
                        ),
                      )
                    : ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(release.heading, style: heading),
                        subtitle: Text(
                          '${release.entries.length} ${release.entries.length == 1 ? 'change' : 'changes'}',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          4,
                        ),
                        children: [entries(release)],
                      ),
              ),
          ],
        );
      },
    ),
  );
}
