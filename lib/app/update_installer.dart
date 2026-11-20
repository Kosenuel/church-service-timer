import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:church_service_timer/app/update_checker.dart';
import 'package:pointycastle/digests/sha256.dart';

/// What a newer release offers a PC.
sealed class WindowsUpdate {
  const WindowsUpdate();
}

/// The release has the Windows installer, which the app can download,
/// check and start. [checksum] is its `.sha256` file, when published.
class InstallerOffered extends WindowsUpdate {
  final ReleaseAsset installer;
  final ReleaseAsset? checksum;
  const InstallerOffered(this.installer, this.checksum);
}

/// The release has nothing the app can start by itself: only the zip
/// ([zip] true), or no Windows file at all. The release page is the way.
class InstallerNotOffered extends WindowsUpdate {
  final bool zip;
  const InstallerNotOffered({required this.zip});
}

/// The installer for [update], named as scripts/Package-Windows.ps1 names
/// it. Only that exact name is accepted, so a file with a different
/// version, or one that is not an installer, is never started.
WindowsUpdate windowsUpdateIn(UpdateAvailable update) {
  final base = 'Church-Service-Timer-${update.version}-windows';
  ReleaseAsset? named(String name) {
    for (final asset in update.assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  final installer = named('$base-setup.exe');
  if (installer == null) {
    return InstallerNotOffered(zip: named('$base-x64.zip') != null);
  }
  return InstallerOffered(installer, named('$base-setup.exe.sha256'));
}

/// An installer downloaded and checked, ready to start.
class DownloadedInstaller {
  final String path, version;

  /// Whether its SHA-256 was checked as well as its size. False when the
  /// release published no checksum.
  final bool hashChecked;
  const DownloadedInstaller(
    this.path,
    this.version, {
    required this.hashChecked,
  });
}

/// Why a download did not produce an installer. [message] is a whole
/// sentence for the operator.
class DownloadFailed implements Exception {
  final String message;
  const DownloadFailed(this.message);
  @override
  String toString() => message;
}

/// The operator pressed Cancel.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// A file being written in a new temporary folder.
abstract class UpdateFile {
  /// Where it is on the PC.
  String get path;
  Future<void> add(List<int> bytes);
  Future<void> close();

  /// Removes the file and its folder.
  Future<void> delete();
}

/// The calls that reach the network, the disk and Windows. The real one is
/// lib/windows/windows_updates.dart; tests use a fake.
abstract class UpdateFiles {
  /// Downloads [url] (https only), following GitHub's redirect to where
  /// the file is stored. Errors arrive on the stream.
  Stream<List<int>> download(String url);

  /// Creates [name] in a new temporary folder.
  Future<UpdateFile> create(String name);

  /// Starts the installer at [path], as if it had been double-clicked;
  /// false when Windows would not start it.
  Future<bool> launch(String path);
}

/// Downloads a newer version's installer for a PC, checks it and starts
/// it. Nothing here happens unless the operator presses Download and
/// install, and the installer is only started after they confirm.
class UpdateInstaller {
  final UpdateFiles files;

  /// Closes the app once the installer has started.
  final Future<void> Function() quit;
  UpdateInstaller(this.files, {required this.quit});

  /// A downloaded checksum file is one line; anything longer is not one.
  static const _checksumLimit = 4096;

  /// No installer is anywhere near this big; refusing larger ones stops a
  /// strange answer filling the disk.
  static const maxInstallerBytes = 500 << 20;

  /// Downloads [offer] for version [version], reporting bytes received
  /// out of the expected size through [progress], and checks it against
  /// the size GitHub lists and the SHA-256 the release publishes. Throws
  /// [DownloadFailed], or [DownloadCancelled] once [cancel] completes.
  /// A file that fails a check is deleted.
  Future<DownloadedInstaller> download(
    InstallerOffered offer,
    String version, {
    required void Function(int received, int total) progress,
    required Future<void> cancel,
  }) async {
    final asset = offer.installer;
    if (asset.size > maxInstallerBytes) {
      throw const DownloadFailed(
        'The installer listed for this version is far too large, so it was not downloaded.',
      );
    }
    var cancelled = false;
    unawaited(cancel.then((_) => cancelled = true));

    // The published checksum first: it is small, and without it the
    // large download would be wasted.
    final expected = await _expectedHash(offer, cancel);
    if (cancelled) throw const DownloadCancelled();

    final file = await files.create(asset.name);
    try {
      final digest = SHA256Digest();
      var received = 0;
      progress(0, asset.size);
      await _receive(files.download(asset.url), cancel, (chunk) async {
        received += chunk.length;
        if (received > asset.size) {
          throw const DownloadFailed(
            'The download was larger than GitHub said it would be, so it was not used. Try again later, or use the release page.',
          );
        }
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        digest.update(bytes, 0, bytes.length);
        await file.add(chunk);
        progress(received, asset.size);
      });
      await file.close();
      if (received != asset.size) {
        throw const DownloadFailed(
          'The download was not complete (its size does not match the release), so it was not used. Try again.',
        );
      }
      if (expected != null) {
        final hash = Uint8List(32);
        digest.doFinal(hash, 0);
        final hex = [
          for (final b in hash) b.toRadixString(16).padLeft(2, '0'),
        ].join();
        if (hex != expected) {
          throw const DownloadFailed(
            'The download does not match the checksum published with the release, so it was not used. Try again later, or use the release page.',
          );
        }
      }
      return DownloadedInstaller(
        file.path,
        version,
        hashChecked: expected != null,
      );
    } catch (_) {
      try {
        await file.close();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// The SHA-256 to check against: the release's `.sha256` file, and
  /// GitHub's own record of the file; when both exist they must agree.
  /// Null when the release has neither.
  Future<String?> _expectedHash(
    InstallerOffered offer,
    Future<void> cancel,
  ) async {
    final listed = offer.installer.sha256;
    final checksum = offer.checksum;
    if (checksum == null) return listed;
    if (checksum.size > _checksumLimit) {
      throw const DownloadFailed(
        'The checksum published with this version could not be read, so the installer was not downloaded.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await _receive(files.download(checksum.url), cancel, (chunk) async {
      bytes.add(chunk);
      if (bytes.length > _checksumLimit) {
        throw const DownloadFailed(
          'The checksum published with this version could not be read, so the installer was not downloaded.',
        );
      }
    });
    // `sha256sum` and Package-Windows.ps1 write "<hash>  <file name>".
    final line = utf8.decode(bytes.takeBytes(), allowMalformed: true).trim();
    final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(\S+)$').firstMatch(line);
    final published = match?.group(1)?.toLowerCase();
    if (published == null || match!.group(2) != offer.installer.name) {
      throw const DownloadFailed(
        'The checksum published with this version could not be read, so the installer was not downloaded.',
      );
    }
    if (listed != null && listed != published) {
      throw const DownloadFailed(
        'The checksum published with this version does not match GitHub’s record of the installer, so it was not downloaded.',
      );
    }
    return published;
  }

  /// Feeds [stream] to [each] until it ends, failing when no data arrives
  /// for 30 seconds, and stopping at once when [cancel] completes.
  Future<void> _receive(
    Stream<List<int>> stream,
    Future<void> cancel,
    Future<void> Function(List<int> chunk) each,
  ) async {
    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    Timer? idle;
    void fail(Object error) {
      idle?.cancel();
      if (done.isCompleted) return;
      done.completeError(
        error is DownloadFailed || error is DownloadCancelled
            ? error
            : const DownloadFailed(
                'The download stopped. Check the internet connection and try again.',
              ),
      );
      unawaited(subscription.cancel());
    }

    void waitForData() {
      idle?.cancel();
      idle = Timer(
        const Duration(seconds: 30),
        () => fail(TimeoutException('No data')),
      );
    }

    subscription = stream.listen(
      (chunk) {
        idle?.cancel();
        subscription.pause();
        each(chunk).then((_) {
          if (done.isCompleted) return;
          waitForData();
          subscription.resume();
        }, onError: fail);
      },
      onError: fail,
      onDone: () {
        idle?.cancel();
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    waitForData();
    unawaited(cancel.then((_) => fail(const DownloadCancelled())));
    return done.future;
  }

  /// Starts the downloaded installer and closes the app so it can replace
  /// the app's files. Throws [DownloadFailed] when Windows would not start
  /// it; the app then stays open.
  Future<void> install(DownloadedInstaller installer) async {
    if (!await files.launch(installer.path)) {
      throw DownloadFailed(
        'Windows would not start the installer. It is saved at ${installer.path}',
      );
    }
    await quit();
  }
}
