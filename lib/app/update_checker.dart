import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Where published versions are listed: the public guide repository's
/// releases, which is also where people download the app.
const latestReleaseUrl =
    'https://api.github.com/repos/ImmanuelOkose/church-service-timer-guide/releases/latest';

/// Opened when a release does not say where its own page is.
const downloadPageUrl =
    'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/latest';

/// The only place a release's own page may be; anything else is ignored.
const _releasePagePrefix =
    'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/';

/// The only place a release's files may download from.
const releaseDownloadPrefix =
    'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/download/';

/// The release's files that are on the guide repository, with a sensible
/// name and size. Anything else in the answer is ignored.
List<ReleaseAsset> _assets(Object? listed) {
  if (listed is! List) return const [];
  final found = <ReleaseAsset>[];
  for (final item in listed) {
    if (item is! Map) continue;
    final name = item['name'], url = item['browser_download_url'];
    final size = item['size'], digest = item['digest'];
    if (name is! String ||
        url is! String ||
        size is! int ||
        size <= 0 ||
        !url.startsWith(releaseDownloadPrefix) ||
        !url.endsWith('/${Uri.encodeComponent(name)}')) {
      continue;
    }
    final hash = digest is String
        ? RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digest)?.group(1)
        : null;
    found.add(ReleaseAsset(name, url, size, sha256: hash?.toLowerCase()));
  }
  return found;
}

/// The x.y.z of a version such as `0.32.0 (37)` or a tag such as `v0.32.0`.
/// The build number in brackets is ignored. Null when [text] is not a
/// version.
List<int>? versionNumbers(String text) {
  final match = RegExp(
    r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})(?: \(.*\))?$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Below zero when version [a] is older than [b], zero when they are the
/// same, above zero when it is newer.
int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

/// What a check for a newer version found.
sealed class UpdateResult {
  const UpdateResult();
}

/// This device has the newest published version. [version] is the one
/// installed, as x.y.z.
class UpToDate extends UpdateResult {
  final String version;
  const UpToDate(this.version);
}

/// One file attached to a release, as GitHub lists it.
class ReleaseAsset {
  /// The file name, for example `Church-Service-Timer-0.33.0.apk`.
  final String name;

  /// Where it downloads from: always on the guide repository's releases.
  final String url;

  /// Its size in bytes, as GitHub reports it.
  final int size;

  /// The SHA-256 GitHub worked out when the file was uploaded, as 64
  /// lower-case hex digits; null when the answer did not include one.
  final String? sha256;
  const ReleaseAsset(this.name, this.url, this.size, {this.sha256});
}

/// A newer [version] (x.y.z) is published; [page] is where to download it.
/// [assets] are the release's files that download from the guide
/// repository (anything listed elsewhere is left out).
class UpdateAvailable extends UpdateResult {
  final String version, page;
  final List<ReleaseAsset> assets;
  const UpdateAvailable(this.version, this.page, [this.assets = const []]);
}

/// The check could not be made, or its answer made no sense.
class UpdateUnknown extends UpdateResult {
  const UpdateUnknown();
}

/// Fetches the text at an https address; null when it could not be read.
typedef FetchText = Future<String?> Function(String url);

/// Asks GitHub which version is the newest, when the person asks for it in
/// Settings › About. Nothing here runs on its own, and nothing about the
/// device or the church is sent: it is one plain GET. Downloading a new
/// version, on a PC, is update_installer.dart, and only when asked.
class UpdateChecker {
  final FetchText fetch;
  const UpdateChecker([this.fetch = fetchOverHttps]);

  /// A checker that never uses the network, for devices and tests that
  /// have none.
  const UpdateChecker.offline() : fetch = _nothing;
  static Future<String?> _nothing(String url) async => null;

  /// Compares the newest published version with [installed], for example
  /// `0.32.0 (37)`. Never throws.
  Future<UpdateResult> check(String installed) async {
    try {
      final mine = versionNumbers(installed);
      if (mine == null) return const UpdateUnknown();
      final text = await fetch(latestReleaseUrl);
      if (text == null) return const UpdateUnknown();
      final release = jsonDecode(text);
      if (release is! Map) return const UpdateUnknown();
      final tag = release['tag_name'];
      final latest = tag is String ? versionNumbers(tag) : null;
      // A tag with brackets is not one of ours.
      if (latest == null || (tag as String).contains('(')) {
        return const UpdateUnknown();
      }
      if (compareVersions(latest, mine) <= 0) return UpToDate(mine.join('.'));
      final page = release['html_url'];
      return UpdateAvailable(
        latest.join('.'),
        page is String && page.startsWith(_releasePagePrefix)
            ? page
            : downloadPageUrl,
        _assets(release['assets']),
      );
    } catch (_) {
      return const UpdateUnknown();
    }
  }

  /// One GET with a generic User-Agent and no cookies, given up after
  /// eight seconds. Null on any failure.
  static Future<String?> fetchOverHttps(String url) async {
    const limit = Duration(seconds: 8);
    final client = HttpClient()
      ..connectionTimeout = limit
      ..userAgent = 'church-service-timer';
    try {
      return await () async {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github+json',
        );
        final response = await request.close();
        if (response.statusCode != 200) {
          await response.drain<void>();
          return null;
        }
        // A release description is a few kilobytes; refuse anything huge.
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
          if (bytes.length > 1 << 20) return null;
        }
        return utf8.decode(bytes.takeBytes());
      }().timeout(limit);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
