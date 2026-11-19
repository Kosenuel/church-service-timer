import 'package:church_service_timer/app/update_checker.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The page behind Settings › About › Check for updates. It is opened by
/// pressing that row, asks once, and says what it found. It never
/// downloads anything: a newer version is a button to the download page.
class UpdateNotice extends StatefulWidget {
  final UpdateChecker checker;

  /// The version running now, for example `0.32.0 (37)`.
  final String installed;

  /// Opens an https page in the browser; false when none could.
  final Future<bool> Function(String url) openPage;
  const UpdateNotice({
    super.key,
    required this.checker,
    required this.installed,
    required this.openPage,
  });

  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice> {
  UpdateResult? result;

  /// Shown when no browser could open the download page.
  String? address;

  @override
  void initState() {
    super.initState();
    widget.checker.check(widget.installed).then((found) {
      if (mounted) setState(() => result = found);
    });
  }

  Future<void> open(String page) async {
    var opened = false;
    try {
      opened = await widget.openPage(page);
    } catch (_) {}
    if (mounted) setState(() => address = opened ? null : page);
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final found = result;
    final line = switch (found) {
      null => 'Checking…',
      UpToDate(:final version) => 'You have the latest version ($version)',
      UpdateAvailable(:final version) => 'Version $version is available',
      UpdateUnknown() => 'Could not check. This device may be offline.',
    };
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
            style: text.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 16),
          ordinarySize(
            context,
            FilledButton.icon(
              key: const ValueKey('update-open-download'),
              onPressed: () => open(found.page),
              icon: const Icon(Icons.open_in_new, size: 20),
              label: const Text('Open the download page'),
            ),
          ),
          if (address != null) ...[
            const SizedBox(height: 12),
            Text(
              'Could not open a browser. The download page is at $address',
              style: text.bodyMedium?.copyWith(color: colors.muted),
            ),
          ],
        ],
      ],
    );
  }
}
