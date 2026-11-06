import 'package:church_service_timer/domain/domain.dart';

/// Local shortcuts, keyed by saved program ID. Portable programs
/// and backups do not carry another operator's favourites or usage history.
class ProgramLibrary {
  final Set<String> favourites;
  final Map<String, int> recent;
  ProgramLibrary({Set<String>? favourites, Map<String, int>? recent})
    : favourites = favourites ?? {},
      recent = recent ?? {};
  factory ProgramLibrary.fromJson(Json j) {
    final pins = j['favourites'] ?? <dynamic>[];
    final times = j['recent'] ?? <String, dynamic>{};
    require(
      pins is List && pins.every((v) => v is String),
      'Invalid program favourites.',
    );
    require(
      times is Map &&
          times.entries.every(
            (e) => e.key is String && e.value is int && e.value >= 0,
          ),
      'Invalid recent programs.',
    );
    return ProgramLibrary(
      favourites: Set<String>.from(pins),
      recent: Map<String, int>.from(times),
    );
  }
  Json toJson() => {'favourites': favourites.toList(), 'recent': recent};
  void remove(String id) {
    favourites.remove(id);
    recent.remove(id);
  }

  List<Timeline> find(List<Timeline> programs, String query, String filter) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final result = programs.where((p) {
      final text =
          '${p.name} ${p.type} ${p.segments.map((s) => '${s.name} ${s.speaker}').join(' ')}'
              .toLowerCase();
      return words.every(text.contains) &&
          (filter != 'favourites' || favourites.contains(p.id)) &&
          (filter != 'recent' || recent.containsKey(p.id)) &&
          (filter != 'rehearsal' || p.type == 'rehearsal');
    }).toList();
    result.sort((a, b) {
      if (filter != 'recent') {
        final pin =
            (favourites.contains(b.id) ? 1 : 0) -
            (favourites.contains(a.id) ? 1 : 0);
        if (pin != 0) return pin;
      }
      final used = (recent[b.id] ?? -1).compareTo(recent[a.id] ?? -1);
      return used != 0
          ? used
          : programs.indexOf(a).compareTo(programs.indexOf(b));
    });
    return result;
  }
}
