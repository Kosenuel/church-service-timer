import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/feedback/feedback_message.dart';

class FeedbackCenterPage extends StatefulWidget {
  final AppController controller;
  const FeedbackCenterPage({super.key, required this.controller});
  @override
  State<FeedbackCenterPage> createState() => _FeedbackCenterPageState();
}

class _FeedbackCenterPageState extends State<FeedbackCenterPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      message = TextEditingController(),
      contact = TextEditingController();
  bool busy = false, issue = false;
  String? status;
  String? diagnostics;

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    contact.dispose();
    super.dispose();
  }

  String? validate(
    String? value,
    String label,
    int limit, {
    bool multiline = false,
  }) {
    try {
      FeedbackMessage.checked(value ?? '', limit, label, multiline: multiline);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> prepare({bool copy = false}) async {
    if (busy || !form.currentState!.validate()) return;
    final feedback = FeedbackMessage(
      title: title.text,
      message: message.text,
      contact: contact.text,
      version: widget.controller.appVersion,
      diagnostics: diagnostics,
    );
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      status = null;
      issue = false;
    });
    try {
      if (copy) {
        await Clipboard.setData(ClipboardData(text: feedback.copyText));
        if (mounted)
          setState(
            () => status =
                'Feedback copied. Paste it into an email to $feedbackRecipient.',
          );
      } else {
        final opened = await widget.controller.port.composeFeedback(
          feedback.subject,
          feedback.body,
        );
        if (mounted)
          setState(() {
            issue = !opened;
            status = opened
                ? 'Email app opened. Review the message and tap Send there. This app cannot confirm delivery. Your text is still here.'
                : 'No email app is available. Install or configure one, or use Copy feedback and email it to $feedbackRecipient. Your text is still here.';
          });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          issue = true;
          status = copy
              ? 'Could not copy feedback. Your text is still here; please try again.'
              : 'Could not open your email app. Your text is still here. Try again or use Copy feedback.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clearDraft() async {
    final clear = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => AlertDialog(
        title: const Text('Clear feedback draft?'),
        content: const Text(
          'Remove the title, message and contact from this screen? An email already opened in another app is unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructiveFilled(),
            child: const Text('Clear draft'),
          ),
        ],
      ),
    );
    if (clear != true || !mounted) return;
    title.clear();
    message.clear();
    contact.clear();
    form.currentState!.reset();
    setState(() {
      status = null;
      issue = false;
      diagnostics = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      bottom: widget.controller.liveSession.active
          ? RunningServiceBar.forContext(context, controller: widget.controller)
          : null,
      title: const Text('Feedback centre'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tell us what happened.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your complaint or suggestion will be prepared for $feedbackRecipient. Review and send it from your email app.',
                    style: TextStyle(color: appColors(context).muted),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const ValueKey('feedback-title'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: title,
                    enabled: !busy,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'A short summary',
                    ),
                    validator: (v) => validate(v, 'Title', 120),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('feedback-message'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: message,
                    enabled: !busy,
                    maxLength: 4000,
                    minLines: 5,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                      hintText: 'What happened? What did you expect?',
                    ),
                    validator: (v) =>
                        validate(v, 'Message', 4000, multiline: true),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('feedback-contact'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: contact,
                    enabled: !busy,
                    maxLength: 120,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Contact (email or phone)',
                      helperText: 'How can we reach you?',
                    ),
                    validator: (v) => validate(v, 'Contact', 120),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'App version ${widget.controller.appVersion} is included. Nothing is sent until you tap Send in your email app.',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    key: const ValueKey('feedback-diagnostics'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include optional diagnostics'),
                    subtitle: const Text(
                      'Connection, notification status and error categories. No church content, credentials or private notes.',
                    ),
                    value: diagnostics != null,
                    onChanged: busy
                        ? null
                        : (value) => setState(
                            () => diagnostics = value
                                ? widget.controller.feedbackDiagnostics
                                : null,
                          ),
                  ),
                  if (diagnostics != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(
                        'Review the details included in your email:\n\n$diagnostics',
                        key: const ValueKey('diagnostics-preview'),
                      ),
                    ),
                  if (status != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        status!,
                        key: const ValueKey('feedback-status'),
                        style: TextStyle(
                          color: issue
                              ? appColors(context).warning
                              : appColors(context).accent,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: busy ? null : () => prepare(),
                    icon: const Icon(Icons.mail_outline),
                    label: Text(busy ? 'Preparing…' : 'Open email app'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => prepare(copy: true),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy feedback'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : clearDraft,
                    child: const Text('Clear draft'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
