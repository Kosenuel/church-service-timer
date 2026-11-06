import 'package:church_service_timer/domain/domain.dart';

/// An after-service reflection on a report, such as "Offering took longer
/// because of announcements". It is kept apart from the recorded timings,
/// which it never changes, and is exported or printed only on request.
class ReviewNote {
  static const maxLength = 1000;
  final String text;
  final int editedWall;
  const ReviewNote(this.text, this.editedWall);

  /// Normalises and validates note text; empty text means no note.
  static String clean(Object? value) {
    require(value is String, 'Review note must be text.');
    final text = (value as String).replaceAll('\r\n', '\n').trim();
    require(
      text.runes.length <= maxLength &&
          !RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(text),
      'Review note must contain at most $maxLength characters without control characters.',
    );
    return text;
  }

  factory ReviewNote.fromJson(Object? j) {
    require(j is Map, 'Invalid review note.');
    final m = j as Map;
    require(m['editedWall'] is int, 'Invalid review note date.');
    final text = clean(m['text']);
    require(text.isNotEmpty, 'Review note is empty.');
    return ReviewNote(text, m['editedWall'] as int);
  }

  Json toJson() => {'text': text, 'editedWall': editedWall};
}

extension ReviewNotes on AppState {
  /// The newest review note left on a past service of [program]. Reports
  /// match by program ID, or by name for reports saved before IDs.
  ({ReviewNote note, ServiceReport report})? latestReviewFor(Timeline program) {
    ServiceReport? newest;
    bool same(ServiceReport r) {
      final id = r.program?.id ?? '';
      return id.isNotEmpty && program.id.isNotEmpty
          ? id == program.id
          : r.name == program.name;
    }

    // Later in the list means saved later, which breaks ties on end time.
    for (final r in reports) {
      if (r.review == null || !same(r)) continue;
      if (newest == null || r.endedWall >= newest.endedWall) newest = r;
    }
    return newest == null ? null : (note: newest.review!, report: newest);
  }

  /// Sets or, with empty text, removes the review note on a report.
  void setReviewNote(String reportId, String text, int at) {
    final i = reports.indexWhere((r) => r.id == reportId);
    require(i >= 0, 'This report was removed.');
    final clean = ReviewNote.clean(text);
    reports[i] = reports[i].withReview(
      clean.isEmpty ? null : ReviewNote(clean, at),
    );
  }
}
