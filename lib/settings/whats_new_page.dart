import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';

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
  const WhatsNewPage({super.key, this.load = bundledChangelog});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What’s new')),
    // A wide window keeps the notes to a readable line length.
    body: isWideWindow(context)
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ReleaseNotesView(load: load),
            ),
          )
        : ReleaseNotesView(load: load),
  );
}

// Decoded here rather than with rootBundle.loadString, which moves files
// over 50 KB to a background isolate. The changelog keeps growing past
// that; decoding it directly is quick and behaves the same everywhere.
Future<String> bundledChangelog() async =>
    utf8.decode((await rootBundle.load('CHANGELOG.md')).buffer.asUint8List());

/// Where the release notes beside About come from. Tests replace it with
/// fixed notes, so their screenshots do not change with every release.
Future<String> Function() changelogSource = bundledChangelog;

/// The release notes: the two newest releases open, older ones folded
/// away. [flat] draws them without cards and without scrolling of their
/// own, for a pane that already has a surface and scrolls.
class ReleaseNotesView extends StatefulWidget {
  final Future<String> Function()? load;
  final bool flat;
  const ReleaseNotesView({super.key, this.load, this.flat = false});
  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  late Future<String> notes = (widget.load ?? changelogSource)();

  @override
  void didUpdateWidget(ReleaseNotesView old) {
    super.didUpdateWidget(old);
    if (old.load != widget.load) notes = (widget.load ?? changelogSource)();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: notes,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return const Center(child: Text('Release notes are unavailable.'));
      if (!snapshot.hasData)
        return widget.flat
            ? const SizedBox.shrink()
            : const Center(child: CircularProgressIndicator());
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
      Widget folded(ReleaseNotes release, {bool flat = false}) => ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: flat ? EdgeInsets.zero : null,
        title: Text(release.heading, style: heading),
        subtitle: Text(
          '${release.entries.length} ${release.entries.length == 1 ? 'change' : 'changes'}',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
        childrenPadding: flat
            ? const EdgeInsets.only(bottom: 4)
            : const EdgeInsets.fromLTRB(16, 0, 16, 4),
        children: [entries(release)],
      );
      if (widget.flat) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, release) in releases.indexed) ...[
              if (i > 0) const AppDivider(indent: 0, endIndent: 0),
              if (i < 2)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 4),
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
              else
                folded(release, flat: true),
            ],
          ],
        );
      }
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
                  : folded(release),
            ),
        ],
      );
    },
  );
}
