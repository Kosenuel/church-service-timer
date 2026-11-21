/// The app version this device last showed the "what's new" notice for.
library;

/// A version such as `0.36.0`, `0.36.0-beta.1` or `0.36.0 (37)`. The build
/// number in brackets is ignored; a pre-release sorts before its release.
class SemanticVersion implements Comparable<SemanticVersion> {
  final List<int> numbers;
  final List<String> pre;
  const SemanticVersion(this.numbers, this.pre);

  static final _pattern = RegExp(
    r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})(?:-([0-9A-Za-z.-]{1,32}))?(?: \(.*\))?$',
  );

  /// Null when [text] is not a version.
  static SemanticVersion? tryParse(Object? text) {
    if (text is! String) return null;
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return SemanticVersion([
      for (var i = 1; i <= 3; i++) int.parse(m.group(i)!),
    ], m.group(4)?.split('.') ?? const []);
  }

  /// `x.y.z` or `x.y.z-pre`, without the build number.
  @override
  String toString() =>
      pre.isEmpty ? numbers.join('.') : '${numbers.join('.')}-${pre.join('.')}';

  @override
  int compareTo(SemanticVersion other) {
    for (var i = 0; i < 3; i++) {
      if (numbers[i] != other.numbers[i]) return numbers[i] - other.numbers[i];
    }
    if (pre.isEmpty || other.pre.isEmpty) {
      return pre.isEmpty == other.pre.isEmpty ? 0 : (pre.isEmpty ? 1 : -1);
    }
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final a = int.tryParse(pre[i]), b = int.tryParse(other.pre[i]);
      final c = a != null && b != null
          ? a.compareTo(b)
          : a != null
          ? -1
          : b != null
          ? 1
          : pre[i].compareTo(other.pre[i]);
      if (c != 0) return c;
    }
    return pre.length - other.pre.length;
  }
}

/// A stored last seen version, or null when it is missing or unexpected,
/// which reads as nothing seen.
String? readSeenVersion(Object? value) =>
    SemanticVersion.tryParse(value) != null &&
        value is String &&
        !value.contains(' ')
    ? value
    : null;
