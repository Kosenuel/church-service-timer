import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

/// The system's Open and Save windows. Each returns a full path, or null
/// when the person closed the window without choosing.
abstract class FileDialogs {
  Future<String?> open({
    required String label,
    required List<String> extensions,
  });
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
  });
  Future<String?> folder();
}

/// The standard Windows dialogs, through the file_selector plugin.
class SystemFileDialogs implements FileDialogs {
  const SystemFileDialogs();
  @override
  Future<String?> open({
    required String label,
    required List<String> extensions,
  }) async => (await FileSelectorPlatform.instance.openFile(
    acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
  ))?.path;

  @override
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
  }) async => (await FileSelectorPlatform.instance.getSaveLocation(
    acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
    options: SaveDialogOptions(suggestedName: suggestedName),
  ))?.path;

  @override
  Future<String?> folder() => FileSelectorPlatform.instance
      .getDirectoryPathWithOptions(const FileDialogOptions());
}

String fileName(String path) => path.split(RegExp(r'[\\/]')).last;

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Reads a program or backup file as `{name, content}`, with the rules the
/// Android picker applies: CSV or JSON only, at most [maxBytes], and valid
/// UTF-8 text.
Future<Map<String, dynamic>> readImportFile(String path, int maxBytes) async {
  final name = fileName(path);
  require(
    const {'csv', 'json'}.contains(_extension(name)),
    'Choose CSV or JSON. Export Excel as CSV first.',
  );
  final file = File(path);
  final tooLarge = 'Import exceeds ${maxBytes ~/ 1048576} MiB';
  require(await file.length() <= maxBytes, tooLarge);
  final bytes = await file.readAsBytes();
  require(bytes.length <= maxBytes, tooLarge);
  final String content;
  try {
    content = utf8.decode(bytes);
  } on FormatException {
    throw RuleError(
      'This file is not UTF-8 text. Save it as "CSV UTF-8" or JSON, then try again.',
    );
  }
  return {'name': name, 'content': content};
}

/// A name that is safe to create in any Windows folder.
String safeFileName(String name) {
  var safe = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (safe.isEmpty) safe = 'file';
  final stem = safe.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem))
    safe = '_$safe';
  return safe;
}

/// A path in [folder] for [name] that does not replace an existing file:
/// "report.pdf", then "report (2).pdf", and so on.
Future<String> freePath(String folder, String name) async {
  final safe = safeFileName(name);
  final dot = safe.lastIndexOf('.');
  final stem = dot <= 0 ? safe : safe.substring(0, dot);
  final ext = dot <= 0 ? '' : safe.substring(dot);
  final separator = Platform.pathSeparator;
  var path = '$folder$separator$safe';
  for (var n = 2; await File(path).exists(); n++) {
    path = '$folder$separator$stem ($n)$ext';
  }
  return path;
}

/// Writes [bytes] completely before the file appears under its name.
Future<void> writeWhole(String path, Uint8List bytes) async {
  final next = File('$path.part');
  await next.writeAsBytes(bytes, flush: true);
  await next.rename(path);
}
