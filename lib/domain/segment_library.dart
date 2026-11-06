import 'package:church_service_timer/domain/domain.dart';

/// How many reusable segments the library keeps.
const segmentLibraryLimit = 50;

List<Segment> readSegmentLibrary(Object? raw) {
  if (raw == null) return [];
  require(
    raw is List && raw.length <= segmentLibraryLimit,
    'Keep at most $segmentLibraryLimit segments in the library.',
  );
  final result = <Segment>[];
  for (final e in raw as List) {
    final s = Segment.fromJson(Map<String, dynamic>.from(e as Map));
    require(
      !result.any((v) => v.name.toLowerCase() == s.name.toLowerCase()),
      'The segment library contains duplicate names.',
    );
    result.add(s);
  }
  return result;
}

extension SegmentLibrary on AppState {
  /// Saves [segment] for reuse, newest first. A segment with the same name
  /// is replaced, so saving again updates it.
  void saveLibrarySegment(Segment segment) {
    require(
      segment.durationMs <= supportedCountdownMs,
      'Keep each segment within 59:59.',
    );
    final existing = segmentLibrary.indexWhere(
      (s) => s.name.toLowerCase() == segment.name.toLowerCase(),
    );
    if (existing >= 0) {
      segmentLibrary.removeAt(existing);
    } else {
      require(
        segmentLibrary.length < segmentLibraryLimit,
        'The segment library is full. Remove one first.',
      );
    }
    segmentLibrary.insert(0, segment);
  }

  /// Removes the library segment named [name]; returns it and its position.
  (int, Segment)? removeLibrarySegment(String name) {
    final i = segmentLibrary.indexWhere((s) => s.name == name);
    if (i < 0) return null;
    return (i, segmentLibrary.removeAt(i));
  }

  /// Puts a removed library segment back where it was.
  void restoreLibrarySegment(int index, Segment segment) {
    require(
      !segmentLibrary.any(
        (s) => s.name.toLowerCase() == segment.name.toLowerCase(),
      ),
      '“${segment.name}” is already in the library.',
    );
    require(
      segmentLibrary.length < segmentLibraryLimit,
      'The segment library is full.',
    );
    segmentLibrary.insert(index.clamp(0, segmentLibrary.length), segment);
  }
}
