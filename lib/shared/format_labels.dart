String clockLabel(int wall) {
  final date = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// "1 segment", "3 segments".
String plural(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';
