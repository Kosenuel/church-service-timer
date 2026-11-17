import 'dart:async';
import 'dart:io';

/// Makes sure only one copy of the app runs for a Windows user.
///
/// Two copies would both write the saved service and overwrite each other.
/// The first copy holds a lock on a file in the data folder. A second copy
/// cannot get the lock, so it leaves a note in the `handoff` folder (the
/// program file it was asked to open, if any) and closes; the first copy
/// sees the note, comes to the front and opens the file.
class SingleInstance {
  final Directory dataDir;
  SingleInstance(this.dataDir);
  RandomAccessFile? _lock;
  Timer? _poll;

  Directory get _handoff =>
      Directory('${dataDir.path}${Platform.pathSeparator}handoff');

  /// True when this is the only copy running; it then stays so until the
  /// process ends.
  bool acquire() {
    try {
      dataDir.createSync(recursive: true);
      final file = File(
        '${dataDir.path}${Platform.pathSeparator}instance.lock',
      ).openSync(mode: FileMode.write);
      try {
        file.lockSync(FileLock.exclusive);
      } catch (_) {
        file.closeSync();
        return false;
      }
      _lock = file;
      return true;
    } catch (_) {
      // If the lock itself cannot be made, running is better than refusing.
      return true;
    }
  }

  /// Called by a second copy: asks the first to come forward and, when
  /// [path] is given, to open that file.
  void handOver(String? path) {
    try {
      _handoff.createSync(recursive: true);
      final name = '${DateTime.now().microsecondsSinceEpoch}-$pid';
      final sep = Platform.pathSeparator;
      File('${_handoff.path}$sep$name.tmp')
        ..writeAsStringSync(path ?? '', flush: true)
        ..renameSync('${_handoff.path}$sep$name.open');
    } catch (_) {
      // Nothing more a second copy can do.
    }
  }

  /// Watches for notes from later copies. [onRequest] gets the file to
  /// open, or null when the other copy was simply started again.
  void listen(void Function(String? path) onRequest) {
    void collect() {
      try {
        if (!_handoff.existsSync()) return;
        final notes =
            _handoff
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.open'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final note in notes) {
          final path = note.readAsStringSync();
          note.deleteSync();
          onRequest(path.isEmpty ? null : path);
        }
      } catch (_) {
        // A note still being written is picked up on the next look.
      }
    }

    // Notes left while no copy was running are stale: discard them.
    try {
      if (_handoff.existsSync()) _handoff.deleteSync(recursive: true);
    } catch (_) {}
    _poll ??= Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => collect(),
    );
  }

  void dispose() {
    _poll?.cancel();
    _poll = null;
    try {
      _lock?.unlockSync();
      _lock?.closeSync();
    } catch (_) {}
    _lock = null;
  }
}
