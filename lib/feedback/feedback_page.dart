import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
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
  void initState() {
    super.initState();
    // The email beside the form in a wide window follows what is typed.
    for (final field in [title, message, contact]) {
      field.addListener(() {
        if (mounted && isWideWindow(context)) setState(() {});
      });
    }
  }

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
                ? deviceText(
                    'Email app opened. Review the message and tap Send there. This app cannot confirm delivery. Your text is still here.',
                  )
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

  /// The email as it stands, for the pane beside the form in a wide
  /// window. A field still empty shows what goes there.
  Widget emailPreview(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    String or(String value, String placeholder) =>
        value.trim().isEmpty ? placeholder : value;
    FeedbackMessage? email;
    try {
      email = FeedbackMessage(
        title: or(title.text, '(your title)'),
        message: or(message.text, '(your message)'),
        contact: or(contact.text, '(how to reach you)'),
        version: widget.controller.appVersion,
        diagnostics: diagnostics,
      );
    } catch (_) {
      email = null;
    }
    Widget line(String name, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              name,
              style: text.bodySmall?.copyWith(color: colors.muted),
            ),
          ),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
    return SidePane(
      key: const ValueKey('feedback-email-preview'),
      title: 'The email you will send',
      note:
          'It opens in your email app for you to read and send. Nothing is sent until you send it there.',
      children: [
        if (email == null)
          Text(
            'Correct the fields marked in the form to see the email.',
            style: text.bodyMedium?.copyWith(color: colors.warning),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                line('To', feedbackRecipient),
                line('Subject', email.subject),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 12),
                  child: AppDivider(indent: 0, endIndent: 0),
                ),
                Text(
                  email.body,
                  style: text.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideWindow(context);
    final fields = <Widget>[
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
        validator: (v) => validate(v, 'Message', 4000, multiline: true),
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
        deviceText(
          'App version ${widget.controller.appVersion} is included. Nothing is sent until you tap Send in your email app.',
        ),
        style: TextStyle(color: appColors(context).muted, fontSize: 13),
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
      // In a wide window the details are in the email beside
      // the form.
      if (diagnostics != null && !wide)
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
    ];
    final send = FilledButton.icon(
      onPressed: busy ? null : () => prepare(),
      icon: const Icon(Icons.mail_outline),
      label: Text(busy ? 'Preparing…' : 'Open email app'),
    );
    final copy = OutlinedButton.icon(
      onPressed: busy ? null : () => prepare(copy: true),
      icon: const Icon(Icons.copy_outlined),
      label: const Text('Copy feedback'),
    );
    final appBar = AppBar(
      bottom: widget.controller.liveSession.active
          ? RunningServiceBar.forContext(context, controller: widget.controller)
          : null,
      title: const Text('Feedback centre'),
    );
    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: SafeArea(
          child: SplitPage(
            mainMaxWidth: 704,
            main: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...fields,
                    const SizedBox(height: 24),
                    // The one main action last, where the eye ends up;
                    // clearing the draft is the quiet one at the left.
                    Row(
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: appColors(context).error,
                          ),
                          onPressed: busy ? null : clearDraft,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear draft'),
                        ),
                        const Spacer(),
                        copy,
                        const SizedBox(width: 10),
                        send,
                      ],
                    ),
                  ],
                ),
              ),
            ),
            side: emailPreview(context),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
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
                    ...fields,
                    const SizedBox(height: 20),
                    send,
                    const SizedBox(height: 8),
                    copy,
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: appColors(context).error,
                        side: BorderSide(
                          color: appColors(context).error.withValues(alpha: .5),
                        ),
                      ),
                      onPressed: busy ? null : clearDraft,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear draft'),
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
}
