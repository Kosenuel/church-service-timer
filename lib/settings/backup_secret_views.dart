import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';

/// Result of the export dialog: null cancels; an empty passphrase means
/// "export without passwords".
class BackupExportChoice {
  final String passphrase;
  const BackupExportChoice(this.passphrase);
  bool get includePasswords => passphrase.isNotEmpty;
}

class BackupExportDialog extends StatefulWidget {
  final bool hasPasswords;
  const BackupExportDialog({super.key, required this.hasPasswords});
  @override
  State<BackupExportDialog> createState() => _BackupExportDialogState();
}

class _BackupExportDialogState extends State<BackupExportDialog> {
  bool include = false;
  final first = TextEditingController(), second = TextEditingController();
  String? problem;
  @override
  void dispose() {
    first.clear();
    second.clear();
    first.dispose();
    second.dispose();
    super.dispose();
  }

  void submit() {
    if (!include) {
      Navigator.pop(context, const BackupExportChoice(''));
      return;
    }
    if (first.text.length < minimumBackupPassphrase) {
      setState(() => problem = 'Use at least 8 characters.');
      return;
    }
    if (first.text != second.text) {
      setState(() => problem = 'The two passphrases do not match.');
      return;
    }
    Navigator.pop(context, BackupExportChoice(first.text));
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: appColors(context).muted);
    return AlertDialog(
      scrollable: true,
      title: const Text('Export backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            key: const ValueKey('include-passwords'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            titleAlignment: ListTileTitleAlignment.top,
            value: include,
            onChanged: widget.hasPasswords
                ? (v) => setState(() {
                    include = v ?? false;
                    problem = null;
                  })
                : null,
            title: const Text('Include saved passwords'),
            subtitle: Text(
              widget.hasPasswords
                  ? 'The LED sign’s device password and Wi-Fi details, encrypted with a passphrase you choose. Paired-device approvals are never included.'
                  : 'No sign passwords are saved on this phone.',
              style: muted,
            ),
          ),
          if (include) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('backup-passphrase'),
              controller: first,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Passphrase'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('backup-passphrase-repeat'),
              controller: second,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Repeat passphrase'),
            ),
            const SizedBox(height: 8),
            Text(
              'You will need this passphrase to restore the passwords. It cannot be recovered; without it, everything else still restores.',
              style: muted,
            ),
          ],
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                problem!,
                style: TextStyle(color: appColors(context).error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: submit, child: const Text('Export')),
      ],
    );
  }
}

/// Asks for the passphrase of a backup's saved passwords. Returns null to skip.
class BackupPassphraseDialog extends StatefulWidget {
  final String? error;
  const BackupPassphraseDialog({super.key, this.error});
  @override
  State<BackupPassphraseDialog> createState() => _BackupPassphraseDialogState();
}

class _BackupPassphraseDialogState extends State<BackupPassphraseDialog> {
  final field = TextEditingController();
  @override
  void dispose() {
    field.clear();
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restore saved passwords?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This backup includes encrypted sign passwords. Enter its passphrase to restore them to this phone, or skip.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('restore-passphrase'),
          controller: field,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Passphrase',
            errorText: widget.error,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Skip'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, field.text),
        child: const Text('Restore passwords'),
      ),
    ],
  );
}
