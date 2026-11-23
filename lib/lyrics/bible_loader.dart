import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter/services.dart';

/// The translations the app can look verses up in. The King James Version
/// comes with the app; later versions can add downloaded files in the
/// same format (see docs/LYRICS-DESIGN.md).
class BibleLibrary {
  BibleLibrary._();

  /// The bundled translations by code, and the asset each is read from.
  static const bundled = {'KJV': 'assets/bible/kjv.txt.gz'};

  static final _loaded = <String, Future<Bible>>{};

  /// The translation with [code], read once and kept.
  static Future<Bible> load([String code = 'KJV']) =>
      _loaded[code] ??= _read(code);

  /// Keeps an already parsed [bible] as the translation of its code, so
  /// the search index's copy is the one lookups read.
  static void adopt(Bible bible) =>
      _loaded[bible.code] = Future<Bible>.value(bible);

  static Future<Bible> _read(String code) async {
    final asset = bundled[code];
    if (asset == null) throw RuleError('The $code is not on this device.');
    try {
      final data = await rootBundle.load(asset);
      final text = utf8.decode(gzip.decode(data.buffer.asUint8List()));
      return Bible.parse(text);
    } catch (e) {
      _loaded.remove(code);
      if (e is RuleError) rethrow;
      throw RuleError('The $code could not be opened.');
    }
  }
}
