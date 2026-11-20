import 'dart:async';

import 'package:church_service_timer/app/update_checker.dart';
import 'package:church_service_timer/app/update_installer.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The page behind Settings › About › Check for updates. It is opened by
/// pressing that row, asks once, and says what it found. On a phone a
/// newer version is a button to the download page. On a PC it can also be
/// downloaded, checked and installed, but only when the operator presses
/// Download and install and then confirms; never by itself.
class UpdateNotice extends StatefulWidget {
  final UpdateChecker checker;

  /// The version running now, for example `0.32.0 (37)`.
  final String installed;

  /// Opens an https page in the browser; false when none could.
  final Future<bool> Function(String url) openPage;

  /// Downloads and starts the installer (a PC); null on a phone.
  final UpdateInstaller? installer;

  /// Why installing must wait, as a sentence (a service is running), or
  /// null when it may go ahead. Asked before downloading and again before
  /// the app closes.
  final String? Function()? installBlocker;

  /// Saves anything still being edited before the app closes; returns a
  /// sentence when that could not be done.
  final Future<String?> Function()? saveFirst;

  /// Asks a question with Cancel and [button]; true when confirmed.
  final Future<bool> Function(String title, String body, String button)?
  confirm;
  const UpdateNotice({
    super.key,
    required this.checker,
    required this.installed,
    required this.openPage,
    this.installer,
    this.installBlocker,
    this.saveFirst,
    this.confirm,
  });

  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice> {
  UpdateResult? result;

  /// Shown when no browser could open the download page.
  String? address;

  /// Set while the installer downloads: bytes so far and expected.
  int? received, total;
  Completer<void>? _cancel;

  /// Downloaded and checked, waiting for the operator to confirm.
  DownloadedInstaller? ready;

  /// One sentence about the last thing that went wrong or was stopped.
  String? problem;

  @override
  void initState() {
    super.initState();
    widget.checker.check(widget.installed).then((found) {
      if (mounted) setState(() => result = found);
    });
  }

  @override
  void dispose() {
    // Leaving the page stops a download; nothing carries on unseen.
    cancelDownload();
    super.dispose();
  }

  Future<void> open(String page) async {
    var opened = false;
    try {
      opened = await widget.openPage(page);
    } catch (_) {}
    if (mounted) setState(() => address = opened ? null : page);
  }

  bool get downloading => _cancel != null;

  Future<void> download(UpdateAvailable update, InstallerOffered offer) async {
    final installer = widget.installer!;
    final blocked = widget.installBlocker?.call();
    if (blocked != null) {
      setState(() => problem = blocked);
      return;
    }
    final cancel = Completer<void>();
    setState(() {
      _cancel = cancel;
      problem = null;
      received = 0;
      total = offer.installer.size;
    });
    try {
      final done = await installer.download(
        offer,
        update.version,
        cancel: cancel.future,
        progress: (got, of) {
          if (mounted && identical(_cancel, cancel)) {
            setState(() {
              received = got;
              total = of;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _cancel = null;
        ready = done;
      });
      await install();
    } on DownloadCancelled {
      if (mounted) {
        setState(() {
          _cancel = null;
          problem = 'Download cancelled. Nothing was installed.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _cancel = null;
          problem = error is DownloadFailed
              ? error.message
              : 'The download stopped. Check the internet connection and try again.';
        });
      }
    }
  }

  void cancelDownload() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  Future<bool> ask(String title, String body, String button) async {
    final asker = widget.confirm;
    if (asker != null) return asker(title, body, button);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(body)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-action'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(button),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Asks, then starts the installer and closes the app.
  Future<void> install() async {
    final done = ready;
    if (done == null) return;
    final blocked = widget.installBlocker?.call();
    if (blocked != null) {
      setState(() => problem = blocked);
      return;
    }
    final checked = done.hashChecked
        ? 'The download matches the size and checksum published with the release.'
        : 'The download matches the size listed with the release. This release has no checksum, so that was all that could be checked.';
    final confirmed = await ask(
      'Install version ${done.version}?',
      'The app will close to install version ${done.version}. Your services, programs, reports and settings are kept. Anything you are editing is saved first and offered again when the app reopens.\n\n'
          'The installer opens in its own window and asks before it changes anything. Windows may warn that the installer is not signed; choose More info, then Run anyway.\n\n'
          '$checked',
      'Close and install',
    );
    if (!confirmed || !mounted) return;
    // A service may have started while the question was open.
    final late = widget.installBlocker?.call();
    if (late != null) {
      setState(() => problem = late);
      return;
    }
    final unsaved = await widget.saveFirst?.call();
    if (!mounted) return;
    if (unsaved != null) {
      setState(() => problem = unsaved);
      return;
    }
    try {
      await widget.installer!.install(done);
    } catch (error) {
      if (mounted) {
        setState(
          () => problem = error is DownloadFailed
              ? error.message
              : 'Windows would not start the installer. It is saved at ${done.path}',
        );
      }
    }
  }

  static String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: colors.muted);
    final found = result;
    final line = switch (found) {
      null => 'Checking…',
      UpToDate(:final version) => 'You have the latest version ($version)',
      UpdateAvailable(:final version) => 'Version $version is available',
      UpdateUnknown() => 'Could not check. This device may be offline.',
    };
    final onPc = widget.installer != null;
    final offer = found is UpdateAvailable && onPc
        ? windowsUpdateIn(found)
        : null;
    final noInstaller = offer is InstallerNotOffered
        ? offer.zip
              ? 'This version is published for Windows only as a zip file, which the app cannot install by itself. Open the release page, download the zip and unzip it over the folder the app is in.'
              : 'This version has no Windows installer the app can use. Open the release page to download it.'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          line,
          key: const ValueKey('update-result'),
          style: text.titleMedium,
        ),
        if (found is UpdateAvailable) ...[
          const SizedBox(height: 8),
          Text(
            'This version keeps working. Update when it suits you, not during a service.',
            style: muted,
          ),
          if (noInstaller != null) ...[
            const SizedBox(height: 8),
            Text(
              noInstaller,
              key: const ValueKey('update-no-installer'),
              style: muted,
            ),
          ],
          const SizedBox(height: 16),
          if (downloading) ...[
            LinearProgressIndicator(
              key: const ValueKey('update-progress'),
              value: (total ?? 0) > 0 ? (received ?? 0) / total! : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading… ${megabytes(received ?? 0)} of ${megabytes(total ?? 0)}',
              key: const ValueKey('update-progress-text'),
              style: muted,
            ),
            const SizedBox(height: 12),
            ordinarySize(
              context,
              OutlinedButton(
                key: const ValueKey('update-cancel'),
                onPressed: cancelDownload,
                child: const Text('Cancel download'),
              ),
            ),
          ] else if (offer is InstallerOffered) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('update-install'),
                  onPressed: ready == null
                      ? () => download(found, offer)
                      : install,
                  icon: const Icon(Icons.download_outlined, size: 20),
                  label: Text(
                    ready == null ? 'Download and install' : 'Install now',
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('update-open-download'),
                  onPressed: () => open(found.page),
                  icon: const Icon(Icons.open_in_new, size: 20),
                  label: const Text('Open release page'),
                ),
              ],
            ),
            if (ready != null) ...[
              const SizedBox(height: 8),
              Text(
                'Downloaded and checked. Nothing is installed until you confirm.',
                style: muted,
              ),
            ],
          ] else
            ordinarySize(
              context,
              FilledButton.icon(
                key: const ValueKey('update-open-download'),
                onPressed: () => open(found.page),
                icon: const Icon(Icons.open_in_new, size: 20),
                label: Text(
                  onPc ? 'Open release page' : 'Open the download page',
                ),
              ),
            ),
          if (problem != null) ...[
            const SizedBox(height: 12),
            Text(
              problem!,
              key: const ValueKey('update-problem'),
              style: text.bodyMedium?.copyWith(color: colors.warning),
            ),
          ],
          if (address != null) ...[
            const SizedBox(height: 12),
            Text(
              onPc
                  ? 'Could not open a browser. The release page is at $address'
                  : 'Could not open a browser. The download page is at $address',
              style: muted,
            ),
          ],
        ],
      ],
    );
  }
}
