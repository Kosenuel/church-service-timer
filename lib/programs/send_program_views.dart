import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';

extension SendProgramViews on HomeState {
  /// Sends [program] to paired phones chosen from those connected now.
  Future<void> sendProgramToPhones(Timeline program) async {
    final recipients = c.pairing.programRecipients;
    if (recipients.isEmpty) {
      await showError(
        'No paired phone is connected. Share to screens from Live, let the other phone join, then send.',
      );
      return;
    }
    final chosen = {for (final p in recipients) p.id};
    var notes = false;
    final send = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('Send “${program.name}”'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The phone reviews it before saving. If it already has a program with this name, it can update that one and keep its old version in history.',
                ),
                const SizedBox(height: 8),
                for (final p in recipients)
                  CheckboxListTile(
                    key: ValueKey('send-to:${p.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text(
                      p.role == 'operator' ? 'Operator' : 'Viewer',
                    ),
                    value: chosen.contains(p.id),
                    onChanged: (v) => update(
                      () => v == true ? chosen.add(p.id) : chosen.remove(p.id),
                    ),
                  ),
                const Divider(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include private operator notes'),
                  value: notes,
                  onChanged: (v) => update(() => notes = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('send-program'),
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text(
                chosen.length == 1 ? 'Send' : 'Send to ${chosen.length}',
              ),
            ),
          ],
        ),
      ),
    );
    if (send != true || !mounted) return;
    try {
      final sent = await c.pairing.sendProgram(
        portableProgram(
          (notes ? program : programWithoutNotes(program)).toJson(),
        ),
        chosen,
        c.state.churchName.trim().isEmpty
            ? 'the host device'
            : c.state.churchName.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent == 0
                ? 'Not sent: the phones disconnected.'
                : 'Sent “${program.name}” to ${sent == 1 ? '1 phone' : '$sent phones'}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) await showError('Sending failed: $e');
    }
  }
}

/// On a paired phone: reviews a received program and saves it, updating a
/// program of the same name if the person chooses.
Future<void> reviewReceivedProgram(
  BuildContext context,
  AppController c,
  ReceivedProgram received,
) async {
  final p = received.program;
  final existing = c.state.programNamed(p.name);
  final choice = await showDialog<String>(
    context: context,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (ctx) => AlertDialog(
      title: Text(p.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From ${received.from} · ${p.segments.length} segments · ${durationLabel(p.segments.fold(0, (n, s) => n + s.durationMs))}',
              ),
              const SizedBox(height: 8),
              for (final s in p.segments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${s.durationText} · ${s.name}'),
                ),
              const SizedBox(height: 12),
              Text(
                existing == null
                    ? deviceText('Save it to this phone’s programs.')
                    : deviceText(
                        'This phone already has “${existing.name}”. Update it (its current version is kept in Version history), or save this one as a copy.',
                      ),
                style: TextStyle(color: appColors(ctx).muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        StackedDialogActions(
          children: [
            FilledButton(
              key: const ValueKey('save-received'),
              onPressed: () =>
                  Navigator.pop(ctx, existing == null ? 'copy' : 'update'),
              child: Text(existing == null ? 'Save' : 'Update mine'),
            ),
            if (existing != null)
              OutlinedButton(
                key: const ValueKey('save-received-copy'),
                onPressed: () => Navigator.pop(ctx, 'copy'),
                child: const Text('Save as copy'),
              ),
            TextButton(
              key: const ValueKey('discard-received'),
              style: TextButton.styleFrom(foregroundColor: destructiveColor),
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard'),
            ),
            TextButton(
              key: const ValueKey('cancel-received'),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    ),
  );
  if (choice == null) return;
  if (choice == 'discard') {
    await c.commit((draft, _) => draft.dismissReceived(received));
    return;
  }
  String? error;
  try {
    await NativeDisplayFonts.prepareState(
      AppState([p], c.state.defaults, Session(id: 'received', anchor: c.now)),
    );
    validateTimelinePixels(p, signFit: c.signFitRequired);
    if (!await c.commit((draft, at) {
      draft.saveReceivedProgram(p, update: choice == 'update', at: at.wall);
      draft.dismissReceived(received);
    })) {
      error = c.error ?? 'The program could not be saved.';
    }
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return;
  if (error != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Please review'),
        content: Text(error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice == 'update'
              ? 'Updated “${existing!.name}”'
              : deviceText('Saved to this phone’s programs'),
        ),
      ),
    );
}

/// Cards for programs other phones sent, until each is reviewed. Shown on
/// the paired screen and on Programs.
class ReceivedProgramCards extends StatelessWidget {
  final AppController controller;
  const ReceivedProgramCards({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _cards(context),
  );

  Widget _cards(BuildContext context) {
    final received = controller.state.programInbox;
    if (received.isEmpty) return const SizedBox.shrink();
    final colors = appColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in received)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              key: ValueKey('received-program:${r.program.name}'),
              color: colors.info.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
              // The program's name as the title, so it no longer wraps
              // behind "Program received:"; Review or set it aside here.
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 4),
                leading: Icon(Icons.download_outlined, color: colors.info),
                title: Text(
                  r.program.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('Received from ${r.from} · review to save'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () =>
                          reviewReceivedProgram(context, controller, r),
                      child: const Text('Review'),
                    ),
                    IconButton(
                      key: ValueKey('dismiss-received:${r.program.name}'),
                      tooltip: 'Discard',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Discard “${r.program.name}”?'),
                            content: Text(
                              'The program sent from ${r.from} is not saved. Your own programs are unchanged.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: destructiveFilled(),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true)
                          await controller.commit(
                            (draft, _) => draft.dismissReceived(r),
                          );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
