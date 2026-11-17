import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';

/// A file that is either the old version or the new one, never half of
/// each: the desktop counterpart of Android's AtomicFile.
///
/// A save writes a temporary file, flushes it to disk, keeps the previous
/// version as `.bak` and then renames the new file into place. Reading
/// falls back to `.bak` when the main file is missing or does not pass
/// [valid] (a power cut can leave an empty file behind).
class AtomicTextFile {
  final File file;
  final bool Function(String text) valid;
  AtomicTextFile(this.file, {bool Function(String text)? valid})
    : valid = valid ?? _nonEmpty;
  static bool _nonEmpty(String text) => text.isNotEmpty;

  /// A JSON document; anything that does not parse counts as damaged.
  AtomicTextFile.json(this.file) : valid = _json;
  static bool _json(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  File get _backup => File('${file.path}.bak');
  File get _next => File('${file.path}.tmp');
  Future<void> _queue = Future.value();

  Future<String?> _readValid(File f) async {
    try {
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      return valid(text) ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// The saved text, or null when nothing usable was ever saved.
  Future<String?> read() async {
    await _queue.catchError((_) {});
    return await _readValid(file) ?? await _readValid(_backup);
  }

  /// Replaces the file. Saves run one after another, in the order asked.
  Future<void> write(String text) {
    final done = _queue.catchError((_) {}).then((_) => _write(text));
    _queue = done;
    return done;
  }

  Future<void> _write(String text) async {
    await file.parent.create(recursive: true);
    await _next.writeAsString(text, flush: true);
    // Only a good current version is worth keeping as the fallback.
    if (await _readValid(file) != null) await file.rename(_backup.path);
    await _next.rename(file.path);
  }

  Future<void> delete() {
    final done = _queue.catchError((_) {}).then((_) async {
      for (final f in [file, _backup, _next]) {
        if (await f.exists()) await f.delete();
      }
    });
    _queue = done;
    return done;
  }
}

/// A small JSON object kept in an [AtomicTextFile]: the desktop stand-in
/// for Android's SharedPreferences. Loaded once, saved on every change.
class JsonPrefs {
  final AtomicTextFile _file;
  JsonPrefs(File file) : _file = AtomicTextFile.json(file);
  Json? _values;

  Future<Json> _load() async {
    if (_values != null) return _values!;
    Json loaded = {};
    try {
      final text = await _file.read();
      if (text != null) loaded = Map<String, dynamic>.from(jsonDecode(text));
    } catch (_) {
      // An unreadable preferences file starts again empty.
    }
    return _values ??= loaded;
  }

  Future<Object?> get(String key) async => (await _load())[key];
  Future<bool> contains(String key) async => (await _load()).containsKey(key);
  Future<Json> all() async => Map<String, dynamic>.from(await _load());

  /// Sets every key in [changes]; a null value removes the key.
  Future<void> update(Json changes) async {
    final values = await _load();
    for (final entry in changes.entries) {
      if (entry.value == null) {
        values.remove(entry.key);
      } else {
        values[entry.key] = entry.value;
      }
    }
    await _file.write(jsonEncode(values));
  }

  Future<void> set(String key, Object? value) => update({key: value});
  Future<void> remove(String key) => update({key: null});
}
