import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A 1920 × 1080 slide for projecting: church name, a large QR, the easy
/// name, the guest code and the address, and a small credit.
Future<Uint8List> joinSlidePng({
  required String church,
  required String url,
  required String? localUrl,
  required String? code,
  bool light = false,
}) async {
  const w = 1920.0, h = 1080.0;
  final bg = light ? const Color(0xFFF7F8F4) : const Color(0xFF0B1210);
  final ink = light ? const Color(0xFF14201B) : const Color(0xFFF2F6F1);
  final muted = light ? const Color(0xFF55645D) : const Color(0xFFA8B8AF);
  final accent = light ? const Color(0xFF2E6B2A) : const Color(0xFFC8F56B);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = bg);

  /// Paints [value] at ([x], [y]) and returns its height, so lines stack
  /// whatever the font does.
  double text(
    String value,
    double x,
    double y,
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w500,
    double width = 940,
    FontStyle style = FontStyle.normal,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: color ?? ink,
          fontSize: size,
          fontWeight: weight,
          fontStyle: style,
          height: 1.12,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: width);
    p.paint(canvas, Offset(x, y));
    return p.height;
  }

  // QR on the right, on a white tile so every phone camera reads it.
  const qr = 640.0, qx = 1160.0, qy = 220.0;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(qx - 40, qy - 40, qr + 80, qr + 80),
      const Radius.circular(36),
    ),
    Paint()..color = Colors.white,
  );
  canvas.save();
  canvas.translate(qx, qy);
  QrPainter(
    data: url,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  ).paint(canvas, const Size(qr, qr));
  canvas.restore();

  const left = 120.0;
  var y = 140.0;
  if (church.isNotEmpty) {
    y +=
        text(
          church.toUpperCase(),
          left,
          y,
          38,
          color: accent,
          weight: FontWeight.w700,
        ) +
        18;
  }
  y +=
      text(
        'Follow the\norder of service',
        left,
        y,
        92,
        weight: FontWeight.w700,
      ) +
      24;
  y +=
      text('Scan the code with your phone camera', left, y, 40, color: muted) +
      44;
  if (localUrl != null) {
    y += text('or open', left, y, 32, color: muted) + 4;
    y +=
        text(
          localUrl.replaceFirst('http://', ''),
          left,
          y,
          50,
          weight: FontWeight.w700,
        ) +
        34;
  }
  if (code != null) {
    y += text('Guest code', left, y, 32, color: muted) + 4;
    text(code, left, y, 76, weight: FontWeight.w800, color: accent);
  }
  final address = url.replaceFirst('http://', '');
  text(
    localUrl == null
        ? 'Address: $address'
        : 'If that name does not open: $address',
    left,
    h - 110,
    28,
    color: muted,
    width: 1000,
  );
  text(
    'Created by I-Proton',
    w - 400,
    h - 70,
    24,
    color: muted,
    style: FontStyle.italic,
    width: 360,
  );

  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

bool _plainOk(String v) =>
    v.trim().isNotEmpty && localNameFrom(v) != 'church-timer' ||
    v.trim().toLowerCase() == 'church-timer';

extension WebStageViews on HomeState {
  /// The Web screens section of Screens & devices, while sharing.
  Widget webScreensPanel() {
    final colors = appColors(context);
    final settings = c.webStageSettings;
    final url = c.webStageUrl;
    final local = c.webStageLocalUrl;
    final devices = c.webStage.activeDevices;
    Widget line(String label, String value, {Key? key, bool big = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label, style: TextStyle(color: colors.muted)),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  key: key,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: big ? 22 : 15,
                    letterSpacing: big ? 2 : 0,
                  ),
                ),
              ),
            ],
          ),
        );
    Future<void> update(WebStageSettings next) async {
      if (!await c.setWebStageSettings(next) && mounted)
        await showError(c.error ?? 'Could not save.');
    }

    return KeyedSubtree(
      key: const ValueKey('web-screens'),
      child: panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Web screens',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Any browser on this Wi-Fi (a laptop, TV or phone) can follow the service without the app. Nothing private is shown, and browsers cannot control the service.',
              style: TextStyle(color: colors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (url == null)
              Text(
                c.webStageError ?? 'Starting…',
                style: TextStyle(
                  color: c.webStageError == null ? null : colors.warning,
                ),
              )
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    key: const ValueKey('web-qr'),
                    data: url,
                    size: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (local != null && c.mdns.answered > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Easy name answered ${c.mdns.answered} lookup${c.mdns.answered == 1 ? '' : 's'}',
                    key: const ValueKey('web-name-lookups'),
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ),
              if (local != null)
                line(
                  'Easy name',
                  local.replaceFirst('http://', ''),
                  key: const ValueKey('web-local-name'),
                ),
              line(
                'Address',
                url.replaceFirst('http://', ''),
                key: const ValueKey('web-address'),
              ),
              if (local == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'The easy name is not available on this phone; use the QR or the address.',
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ),
              if (c.joinSlideAddress != null && c.joinSlideAddress != url)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'This phone’s address changed since you exported the join slide. Export it again.',
                    key: const ValueKey('web-slide-stale'),
                    style: TextStyle(
                      color: colors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (settings.orderAccess == OrderAccess.code)
                line(
                  'Guest code',
                  settings.orderCode,
                  key: const ValueKey('web-order-code'),
                  big: true,
                ),
              line(
                'Team code',
                c.webStage.teamCode,
                key: const ValueKey('web-team-code'),
                big: true,
              ),
              Text(
                'The guest code opens Order of service and stays the same each week, for slides and bulletins. The team code opens Stage display and Service overview too, and changes each time you share.',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('export-join-slide'),
                    onPressed: () => exportJoinSlide(),
                    icon: const Icon(Icons.slideshow_outlined),
                    label: const Text('Export join slide'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('web-new-codes'),
                    onPressed: () async {
                      if (!await confirm(
                        'New team code?',
                        'Stage displays and service overviews using the current team code are asked for the new one.',
                        'New team code',
                      ))
                        return;
                      c.webStage.newCodes();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('New team code'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('web-change-order-code'),
                    onPressed: () => changeOrderCode(settings),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Change guest code'),
                  ),
                ],
              ),
            ],
            const Divider(height: 28),
            ChoiceField<OrderAccess>(
              key: const ValueKey('web-order-access'),
              value: settings.orderAccess,
              decoration: const InputDecoration(labelText: 'Order of service'),
              options: [
                for (final a in OrderAccess.values)
                  ChoiceOption(value: a, label: a.label),
              ],
              onChanged: (v) =>
                  v == null ? null : update(settings.copyWith(orderAccess: v)),
            ),
            if (settings.orderAccess == OrderAccess.open)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Anyone on this Wi-Fi can follow without a code. Up to ${WebStageServer.orderViewerLimit} at once.',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
            SwitchListTile(
              key: const ValueKey('web-show-speakers'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show speakers in the order of service'),
              value: settings.showSpeakers,
              onChanged: (v) => update(settings.copyWith(showSpeakers: v)),
            ),
            ListTile(
              key: const ValueKey('web-local-name-edit'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Easy name'),
              subtitle: Text('${settings.localName}.local'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => changeLocalName(settings),
            ),
            Text(
              'Guest Wi-Fi often keeps devices apart; phones on it may not reach this phone. If a printed address stops working, the router gave this phone a new one: ask for it to be reserved, or show the join slide instead.',
              style: TextStyle(color: colors.muted, fontSize: 12, height: 1.4),
            ),
            if (devices.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Following now · ${devices.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final d in devices.where((d) => d.team))
                ListTile(
                  key: ValueKey('web-device:${d.token}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.role == WebRole.stage
                        ? Icons.tv
                        : Icons.view_list_outlined,
                  ),
                  title: Text(d.label),
                  subtitle: Text(d.role.label),
                  trailing: TextButton(
                    onPressed: () => c.webStage.remove(d.token),
                    child: const Text('Remove'),
                  ),
                ),
              if (devices.any((d) => !d.team))
                Text(
                  '${devices.where((d) => !d.team).length} following the order of service',
                  style: TextStyle(color: colors.muted),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> exportJoinSlide() async {
    final url = c.webStageUrl;
    if (url == null) return;
    final light = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export join slide'),
        content: const Text(
          'A 1920 × 1080 image to project or add to your slides. Choose light if your projector washes out dark slides.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            key: const ValueKey('slide-light'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Light'),
          ),
          FilledButton(
            key: const ValueKey('slide-dark'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Dark'),
          ),
        ],
      ),
    );
    if (light == null || !mounted) return;
    try {
      final s = c.webStageSettings;
      final png = await joinSlidePng(
        church: c.state.churchName,
        url: url,
        localUrl: c.webStageLocalUrl,
        code: s.orderAccess == OrderAccess.code ? s.orderCode : null,
        light: light,
      );
      c.joinSlideAddress = url;
      await c.port.shareFiles([
        SharedFile('Join-the-order-of-service.png', png, 'image/png'),
      ], subject: 'Order of service join slide');
    } catch (e) {
      if (mounted) await showError('The slide could not be made: $e');
    }
  }

  Future<String?> askText(
    String title,
    String initial,
    String? Function(String) check, {
    String? help,
  }) async {
    final field = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: field,
            autofocus: true,
            decoration: InputDecoration(helperText: help, errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final problem = check(field.text.trim());
                if (problem != null) {
                  update(() => error = problem);
                } else {
                  Navigator.pop(ctx, field.text.trim());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    return result;
  }

  Future<void> changeOrderCode(WebStageSettings s) async {
    final next = await askText(
      'Guest code',
      s.orderCode,
      (v) => validOrderCode(v) ? null : 'Use 4–8 letters or digits.',
      help: 'People following now are asked for the new code.',
    );
    if (next != null && next != s.orderCode)
      await c.setWebStageSettings(s.copyWith(orderCode: next));
  }

  Future<void> changeLocalName(WebStageSettings s) async {
    final next = await askText(
      'Easy name',
      s.localName,
      (v) => _plainOk(v) ? null : 'Use letters and digits.',
      help:
          'Short is easiest to type, e.g. grace. Spaces become hyphens; .local is added.',
    );
    if (next != null) {
      await c.setWebStageSettings(s.copyWith(localName: localNameFrom(next)));
    }
  }
}
