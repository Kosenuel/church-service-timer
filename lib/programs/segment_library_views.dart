import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

String librarySegmentSummary(Segment s) => [
  formatTime(s.durationMs),
  if (s.speaker.isNotEmpty) s.speaker,
  if (s.notes.isNotEmpty) 'notes',
  if (s.protected) 'protected',
].join(' · ');

/// Picks a saved segment to insert; returns null when cancelled.
Future<Segment?> pickLibrarySegment(BuildContext context, AppController c) =>
    showModalBottomSheet<Segment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _LibraryPicker(controller: c),
    );

class _LibraryPicker extends StatefulWidget {
  final AppController controller;
  const _LibraryPicker({required this.controller});
  @override
  State<_LibraryPicker> createState() => _LibraryPickerState();
}

class _LibraryPickerState extends State<_LibraryPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final matches = [
      for (final s in widget.controller.state.segmentLibrary)
        if (words.every('${s.name} ${s.speaker}'.toLowerCase().contains)) s,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add from library',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('library-search'),
                decoration: const InputDecoration(
                  labelText: 'Search segments',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: matches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No saved segments match.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final s in matches)
                            ListTile(
                              key: ValueKey('library-pick:${s.name}'),
                              leading: const Icon(Icons.bookmark_outline),
                              title: Text(s.name),
                              subtitle: Text(librarySegmentSummary(s)),
                              onTap: () => Navigator.pop(context, s),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension SegmentLibraryViews on HomeState {
  /// Lists saved segments with Remove (and Undo).
  Future<void> openSegmentLibrary() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (pageContext) => AnimatedBuilder(
        animation: c,
        builder: (pageContext, _) {
          final library = c.state.segmentLibrary;
          return Scaffold(
            appBar: AppBar(title: const Text('Segment library')),
            body: ListView(
              padding: EdgeInsets.all(appLayout(pageContext).gap),
              children: [
                Text(
                  'Reusable segments, such as Offering or Announcements, with their duration, speaker and notes. In the program editor, open a segment and choose Save to library, then use From library to add it to any program. Up to $segmentLibraryLimit.',
                  style: TextStyle(color: appColors(pageContext).muted),
                ),
                const SizedBox(height: 16),
                if (library.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No saved segments yet.'),
                  )
                else
                  AppMenuList(
                    key: const ValueKey('segment-library'),
                    children: [
                      for (final s in library)
                        ListTile(
                          key: ValueKey('library-segment:${s.name}'),
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(s.name),
                          subtitle: Text(librarySegmentSummary(s)),
                          trailing: IconButton(
                            key: ValueKey('remove-library:${s.name}'),
                            tooltip: 'Remove from library',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: c.busy || c.corrupt
                                ? null
                                : () => removeLibrarySegment(s),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Future<void> removeLibrarySegment(Segment s) async {
    (int, Segment)? removed;
    if (!await c.commit(
      (draft, _) => removed = draft.removeLibrarySegment(s.name),
    )) {
      if (mounted) await showError(c.error ?? 'Could not remove the segment.');
      return;
    }
    final gone = removed;
    if (gone == null || !mounted) return;
    offerUndo(
      '“${s.name}” removed from the library',
      () =>
          c.commit((draft, _) => draft.restoreLibrarySegment(gone.$1, gone.$2)),
    );
  }
}
