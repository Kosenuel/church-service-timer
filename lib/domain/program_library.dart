import 'package:church_service_timer/domain/domain.dart';

/// Local shortcuts, keyed by the unique saved program name. Portable programs
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
  void rename(String old, String name) {
    if (old == name) return;
    if (favourites.remove(old)) favourites.add(name);
    final time = recent.remove(old);
    if (time != null) recent[name] = time;
  }

  void remove(String name) {
    favourites.remove(name);
    recent.remove(name);
  }

  List<Timeline> find(List<Timeline> programs, String query, String filter) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final result = programs.where((p) {
      final text =
          '${p.name} ${p.type} ${p.segments.map((s) => '${s.name} ${s.speaker}').join(' ')}'
              .toLowerCase();
      return words.every(text.contains) &&
          (filter != 'favourites' || favourites.contains(p.name)) &&
          (filter != 'recent' || recent.containsKey(p.name)) &&
          (filter != 'rehearsal' || p.type == 'rehearsal');
    }).toList();
    result.sort((a, b) {
      if (filter != 'recent') {
        final pin =
            (favourites.contains(b.name) ? 1 : 0) -
            (favourites.contains(a.name) ? 1 : 0);
        if (pin != 0) return pin;
      }
      final used = (recent[b.name] ?? -1).compareTo(recent[a.name] ?? -1);
      return used != 0
          ? used
          : programs.indexOf(a).compareTo(programs.indexOf(b));
    });
    return result;
  }
}
