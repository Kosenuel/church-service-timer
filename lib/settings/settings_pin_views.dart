import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

/// Asks for digits. Returns the PIN, or the string 'recover' when the person
/// chooses "Forgot PIN?".
class PinEntryDialog extends StatefulWidget {
  final String title, message, action;
  final bool allowRecovery;
  final String? error;
  const PinEntryDialog({
    super.key,
    required this.title,
    required this.message,
    this.action = 'Unlock',
    this.allowRecovery = true,
    this.error,
  });
  @override
  State<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<PinEntryDialog> {
  final pin = TextEditingController();
  @override
  void dispose() {
    pin.clear();
    pin.dispose();
    super.dispose();
  }

  void submit() {
    if (SettingsLock.validPin(pin.text)) Navigator.pop(context, pin.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.message),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pin-field'),
          controller: pin,
          autofocus: true,
          obscureText: true,
          maxLength: 8,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, letterSpacing: 6),
          decoration: InputDecoration(
            labelText: 'PIN',
            errorText: widget.error,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => submit(),
        ),
      ],
    ),
    actions: [
      StackedDialogActions(
        children: [
          FilledButton(
            onPressed: SettingsLock.validPin(pin.text) ? submit : null,
            child: Text(widget.action),
          ),
          if (widget.allowRecovery)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'recover'),
              child: const Text('Forgot PIN?'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ],
  );
}

extension SettingsPinViews on HomeState {
  /// Settings, deletion and sign administration ask for the PIN when set.
  Future<bool> ensureSettingsUnlocked({
    String reason = 'Enter the Settings PIN to continue.',
  }) async {
    String? error;
    while (c.settingsLocked && mounted) {
      final wait = c.pinRetryAfter;
      if (wait != null && DateTime.now().isBefore(wait)) {
        error =
            'Too many tries. Wait ${wait.difference(DateTime.now()).inSeconds + 1} s.';
      }
      if (!mounted) return false;
      final value = await showDialog<String>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) => PinEntryDialog(
          title: 'Settings are locked',
          message: reason,
          error: error,
        ),
      );
      if (value == null || !mounted) return false;
      if (value == 'recover') return recoverSettingsPin();
      if (await c.unlockSettings(value)) return true;
      error = c.pinRetryAfter != null
          ? 'Too many tries. Wait 30 s.'
          : 'That PIN is not correct.';
    }
    return !c.settingsLocked;
  }

  Future<bool> recoverSettingsPin() async {
    final field = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Use your recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the one-time recovery code shown when the PIN was set. It removes the PIN; you can then set a new one.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('recovery-field'),
              controller: field,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Recovery code',
                hintText: 'XXXX-XXXX',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, field.text),
            child: const Text('Remove PIN'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    if (code == null || !mounted) return false;
    if (await c.recoverSettings(code)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PIN removed. Set a new one in Settings › Settings PIN.',
            ),
          ),
        );
      return true;
    }
    if (mounted) await showError('That recovery code is not correct.');
    return false;
  }

  /// Bottom navigation and the tablet rail go through here.
  Future<void> goToPage(int value) async {
    if (value == 3 && !await ensureSettingsUnlocked()) return;
    if (mounted) navigatePage(value);
  }

  Future<void> setSettingsPin() async {
    Future<String?> ask(String title, String message, String action) =>
        showDialog<String>(
          context: context,
          animationStyle: reduceAppMotion(context)
              ? AnimationStyle.noAnimation
              : null,
          builder: (_) => PinEntryDialog(
            title: title,
            message: message,
            action: action,
            allowRecovery: false,
          ),
        );
    final first = await ask(
      'Choose a Settings PIN',
      'Use 4 to 8 digits. Live, Programs and Reports stay open; Settings, deleting and sign administration will ask for it.',
      'Next',
    );
    if (first == null || !mounted) return;
    final again = await ask(
      'Repeat the PIN',
      'Enter the same PIN again.',
      'Set PIN',
    );
    if (again == null || !mounted) return;
    if (again != first) {
      await showError('The two PINs did not match. Nothing was changed.');
      return;
    }
    final recovery = await c.setSettingsPin(first);
    if (recovery == null || !mounted) {
      if (mounted) await showError(c.error ?? 'Could not save the PIN.');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'If the PIN is forgotten, this code removes it once. It is shown only now. Write it down and keep it somewhere safe.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              recovery,
              key: const ValueKey('recovery-code'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I have saved it'),
          ),
        ],
      ),
    );
  }

  Widget settingsPinSettings() {
    final colors = appColors(context);
    final on = c.state.settingsLock != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(
          child: Row(
            children: [
              Icon(
                on ? Icons.lock_outline : Icons.lock_open,
                color: on ? colors.accent : colors.muted,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      on ? 'PIN is on' : 'PIN is off',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Locks Settings, deleting programs and reports, and LED sign administration. Live, Programs and Reports stay open for every operator.',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!on)
          FilledButton.icon(
            key: const ValueKey('set-settings-pin'),
            onPressed: c.busy ? null : setSettingsPin,
            icon: const Icon(Icons.pin_outlined),
            label: const Text('Set a PIN'),
          )
        else ...[
          OutlinedButton.icon(
            key: const ValueKey('change-settings-pin'),
            onPressed: c.busy ? null : setSettingsPin,
            icon: const Icon(Icons.pin_outlined),
            label: const Text('Change PIN and recovery code'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('remove-settings-pin'),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            onPressed: c.busy
                ? null
                : () async {
                    if (await confirm(
                      'Turn off the PIN?',
                      'Anyone using this phone will be able to open Settings and delete programs and reports.',
                      'Turn off PIN',
                      destructive: true,
                    ))
                      await c.removeSettingsPin();
                  },
            icon: const Icon(Icons.lock_open),
            label: const Text('Turn off PIN'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'The PIN is stored only as a salted hash on this phone and is never included in backups. Settings lock again whenever the app leaves the screen.',
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ],
    );
  }
}
