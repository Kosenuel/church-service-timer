import 'package:church_service_timer/domain/domain.dart';

/// A program removed by a bulk delete, with what is needed to put it back
/// exactly: its list position, pin and recent use.
class DeletedProgram {
  final int index;
  final Timeline program;
  final bool favourite;
  final int? lastUsed;
  const DeletedProgram(this.index, this.program, this.favourite, this.lastUsed);
}

class DeletedReport {
  final int index;
  final ServiceReport report;
  const DeletedReport(this.index, this.report);
}

/// Bulk deletion of saved programs and reports. Running services and
/// reports keep their own program snapshots, so deleting a saved program
/// never changes an active service or its history.
extension BulkDelete on AppState {
  List<DeletedProgram> deletePrograms(Set<String> names) {
    final removed = <DeletedProgram>[];
    for (var i = 0; i < templates.length; i++) {
      final t = templates[i];
      if (names.contains(t.name))
        removed.add(
          DeletedProgram(
            i,
            t,
            programLibrary.favourites.contains(t.name),
            programLibrary.recent[t.name],
          ),
        );
    }
    require(
      removed.length == names.length,
      'Some selected programs changed. Review the selection again.',
    );
    for (final d in removed.reversed) {
      templates.removeAt(d.index);
      programLibrary.remove(d.program.name);
    }
    return removed;
  }

  void restorePrograms(List<DeletedProgram> removed) {
    for (final d in removed) {
      require(
        !templates.any(
          (t) => t.name.toLowerCase() == d.program.name.toLowerCase(),
        ),
        '“${d.program.name}” already exists, so the programs were not restored.',
      );
    }
    for (final d in removed) {
      templates.insert(d.index.clamp(0, templates.length), d.program);
      if (d.favourite) programLibrary.favourites.add(d.program.name);
      if (d.lastUsed != null)
        programLibrary.recent[d.program.name] = d.lastUsed!;
    }
  }

  List<DeletedReport> deleteReports(Set<String> ids) {
    final removed = <DeletedReport>[
      for (var i = 0; i < reports.length; i++)
        if (ids.contains(reports[i].id)) DeletedReport(i, reports[i]),
    ];
    require(
      removed.length == ids.length,
      'Some selected reports changed. Review the selection again.',
    );
    for (final d in removed.reversed) {
      reports.removeAt(d.index);
    }
    return removed;
  }

  void restoreReports(List<DeletedReport> removed) {
    for (final d in removed) {
      require(
        !reports.any((r) => r.id == d.report.id),
        'These reports were already restored.',
      );
    }
    for (final d in removed) {
      reports.insert(d.index.clamp(0, reports.length), d.report);
    }
  }
}
