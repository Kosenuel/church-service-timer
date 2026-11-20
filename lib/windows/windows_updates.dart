import 'dart:async';
import 'dart:io';

import 'package:church_service_timer/app/update_installer.dart';

/// [UpdateFiles] on a real PC: an https download, a file in the Windows
/// temporary folder, and starting the installer. Nothing is run silently:
/// the installer opens its own window and asks before it does anything.
class WindowsUpdateFiles implements UpdateFiles {
  const WindowsUpdateFiles();

  @override
  Stream<List<int>> download(String url) async* {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const DownloadFailed('Only https downloads are used.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'church-service-timer';
    try {
      final request = await client.getUrl(uri);
      // GitHub answers a release file with a redirect to where it is
      // stored; only https redirects are followed.
      request.followRedirects = false;
      var response = await request.close();
      for (var hops = 0; response.isRedirect && hops < 5; hops++) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        final next = location == null ? null : uri.resolve(location);
        if (next == null || next.scheme != 'https') {
          throw const DownloadFailed(
            'GitHub sent the download somewhere unexpected, so it was stopped.',
          );
        }
        final again = await client.getUrl(next);
        again.followRedirects = false;
        response = await again.close();
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw DownloadFailed(
          'GitHub did not send the file (error ${response.statusCode}). Try again later, or use the release page.',
        );
      }
      yield* response;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<UpdateFile> create(String name) async {
    final folder = await Directory.systemTemp.createTemp(
      'church-service-timer-update-',
    );
    final file = File('${folder.path}${Platform.pathSeparator}$name');
    return _TempFile(folder, file, file.openWrite());
  }

  @override
  Future<bool> launch(String path) async {
    try {
      // Detached, so it keeps running when the app closes. No arguments:
      // the installer shows every step and the operator chooses.
      await Process.start(path, const [], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _TempFile implements UpdateFile {
  final Directory folder;
  final File file;
  final IOSink sink;
  bool _closed = false;
  _TempFile(this.folder, this.file, this.sink);

  @override
  String get path => file.path;
  @override
  Future<void> add(List<int> bytes) async {
    sink.add(bytes);
    // Keeps memory flat however large the file.
    await sink.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await sink.close();
  }

  @override
  Future<void> delete() async {
    await close();
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}
