import 'package:church_service_timer/shared/device_words.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The sizes the join slide can be exported in. Each is laid out for its
/// own shape rather than stretched.
const joinSlideSizes = [
  (
    id: 'hd',
    label: '16:9 HD',
    w: 1920,
    h: 1080,
    note: 'Most TVs and projectors',
  ),
  (id: '4k', label: '16:9 4K', w: 3840, h: 2160, note: 'Large 4K screens'),
  (
    id: 'wide',
    label: '16:10',
    w: 1920,
    h: 1200,
    note: 'Laptops and some projectors',
  ),
  (id: 'classic', label: '4:3', w: 1600, h: 1200, note: 'Older projectors'),
  (
    id: 'portrait',
    label: 'Portrait 9:16',
    w: 1080,
    h: 1920,
    note: 'A TV on its side, phone stories',
  ),
  (
    id: 'square',
    label: 'Square',
    w: 1080,
    h: 1080,
    note: 'Social posts and printing',
  ),
];

/// A slide for projecting: church name, a large QR, the easy name, the
/// guest code and the address, and a small credit. Wide shapes put the QR
/// beside the words, square ones put the title on top, tall ones stack it.
Future<Uint8List> joinSlidePng({
  required String church,
  required String url,
  required String? localUrl,
  required String? code,
  bool light = false,
  int width = 1920,
  int height = 1080,
}) async {
  final w = width.toDouble(), h = height.toDouble();
  final bg = light ? const Color(0xFFF7F8F4) : const Color(0xFF0B1210);
  final ink = light ? const Color(0xFF14201B) : const Color(0xFFF2F6F1);
  final muted = light ? const Color(0xFF55645D) : const Color(0xFFA8B8AF);
  final accent = light ? const Color(0xFF2E6B2A) : const Color(0xFFC8F56B);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = bg);
  final ratio = w / h;
  final shape = ratio >= 1.2
      ? 'wide'
      : ratio >= 0.85
      ? 'square'
      : 'tall';
  // One unit is a pixel on the 1080-pixel-high original design.
  final u = (shape == 'wide' ? h : w) / 1080;
  final m = (shape == 'wide' ? 120 : 80) * u;

  TextPainter layout(
    String value,
    double size,
    double maxWidth, {
    Color? color,
    FontWeight weight = FontWeight.w500,
    FontStyle style = FontStyle.normal,
    int lines = 3,
    TextAlign align = TextAlign.left,
  }) {
    // Shrinks the text until it fits its width in the lines allowed.
    for (var s = size; ; s *= .92) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Roboto',
            color: color ?? ink,
            fontSize: s,
            fontWeight: weight,
            fontStyle: style,
            height: 1.12,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      if (!p.didExceedMaxLines || s < size * .4) return p;
      p.dispose();
    }
  }

  /// Paints [value] at ([x], [y]) and returns its height.
  double text(
    String value,
    double x,
    double y,
    double size,
    double maxWidth, {
    Color? color,
    FontWeight weight = FontWeight.w500,
    FontStyle style = FontStyle.normal,
    int lines = 3,
    TextAlign align = TextAlign.left,
  }) {
    final p = layout(
      value,
      size * u,
      maxWidth,
      color: color,
      weight: weight,
      style: style,
      lines: lines,
      align: align,
    );
    p.paint(canvas, Offset(x, y));
    final height = p.height;
    p.dispose();
    return height;
  }

  void qrAt(double x, double y, double size) {
    // On a white tile so every phone camera reads it.
    final pad = size / 16;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - pad, y - pad, size + 2 * pad, size + 2 * pad),
        Radius.circular(pad * .9),
      ),
      Paint()..color = Colors.white,
    );
    canvas.save();
    canvas.translate(x, y);
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
    ).paint(canvas, Size(size, size));
    canvas.restore();
  }

  double heading(double x, double y, double width) {
    var top = y;
    if (church.isNotEmpty)
      top +=
          text(
            church.toUpperCase(),
            x,
            top,
            38,
            width,
            color: accent,
            weight: FontWeight.w700,
            lines: 1,
          ) +
          18 * u;
    return top +
        text(
          'Follow the\norder of service',
          x,
          top,
          92,
          width,
          weight: FontWeight.w700,
          lines: 2,
        ) +
        24 * u;
  }

  double details(double x, double y, double width) {
    var top = y;
    top +=
        text(
          'Scan the code with your phone camera',
          x,
          top,
          40,
          width,
          color: muted,
          lines: 2,
        ) +
        44 * u;
    if (localUrl != null) {
      top += text('or open', x, top, 32, width, color: muted) + 4 * u;
      top +=
          text(
            localUrl.replaceFirst('http://', ''),
            x,
            top,
            50,
            width,
            weight: FontWeight.w700,
            lines: 1,
          ) +
          34 * u;
    }
    if (code != null) {
      top += text('Guest code', x, top, 32, width, color: muted) + 4 * u;
      top += text(
        code,
        x,
        top,
        76,
        width,
        weight: FontWeight.w800,
        color: accent,
        lines: 1,
      );
    }
    return top;
  }

  // The footer: the address and the credit, on one line when there is
  // room, else the address above the credit.
  final footer = 28 * u;
  final address = url.replaceFirst('http://', '');
  final addressText = localUrl == null
      ? 'Address: $address'
      : 'If that name does not open: $address';
  final credit = layout(
    'Created by I-Proton',
    24 * u,
    400 * u,
    color: muted,
    style: FontStyle.italic,
  );
  final footerTop = h - m * .7 - footer * 1.3;
  credit.paint(canvas, Offset(w - m - credit.width, footerTop + 4 * u));
  final sideBySide = w - 2 * m - credit.width > 900 * u;
  text(
    addressText,
    m,
    sideBySide ? footerTop : footerTop - footer * 1.6,
    28,
    sideBySide ? w - 2 * m - credit.width - 40 * u : w - 2 * m,
    color: muted,
    lines: 1,
  );
  credit.dispose();
  final bottom = (sideBySide ? footerTop : footerTop - footer * 1.6) - 40 * u;

  switch (shape) {
    case 'wide':
      final q = (h * .6).clamp(0.0, w * .37);
      final qx = w - m - q - q / 16;
      final qy = (bottom - q) / 2 + 20 * u;
      qrAt(qx, qy, q);
      final width = qx - q / 16 - 80 * u - m;
      final top = heading(m, m + 20 * u, width);
      details(m, top, width);
    case 'square':
      final full = w - 2 * m;
      final top = heading(m, m, full) + 10 * u;
      final q = math.min(bottom - top - 40 * u, w * .46);
      final qx = w - m - q - q / 16;
      qrAt(qx, top + q / 16, q);
      details(m, top, qx - q / 16 - 40 * u - m);
    default:
      final full = w - 2 * m;
      final top = details(m, heading(m, m * 1.4, full), full);
      final q = math.min(full - 80 * u, bottom - top - 120 * u);
      qrAt((w - q) / 2, top + (bottom - top - q) / 2, q);
  }

  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// The size last used on this phone, offered first next time.
String? lastJoinSlideSize;

bool _plainOk(String v) =>
    v.trim().isNotEmpty && localNameFrom(v) != 'church-timer' ||
    v.trim().toLowerCase() == 'church-timer';

extension WebStageViews on HomeState {
  /// The Web screens section of Screens & devices, while sharing.
  Widget webScreensPanel({bool wide = false}) {
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
                width: wide ? 104 : 120,
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
    Future<void> newTeamCode() async {
      if (!await confirm(
        'New team code?',
        'Stage displays and service overviews using the current team code are asked for the new one.',
        'New team code',
      ))
        return;
      c.webStage.newCodes();
    }

    Future<void> update(WebStageSettings next) async {
      if (!await c.setWebStageSettings(next) && mounted)
        await showError(c.error ?? 'Could not save.');
    }

    final addresses = url == null
        ? const <Widget>[]
        : <Widget>[
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
                  deviceText(
                    'The easy name is not available on this phone; use the QR or the address.',
                  ),
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
            if (c.joinSlideAddress != null && c.joinSlideAddress != url)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  deviceText(
                    'This phone’s address changed since you exported the join slide. Export it again.',
                  ),
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
          ];
    final options = <Widget>[
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
      const SizedBox(height: 12),
      ChoiceField<String>(
        key: const ValueKey('web-stage-layout'),
        value: settings.stageLayout,
        decoration: const InputDecoration(labelText: 'Stage displays show'),
        options: [
          for (final e in stageLayouts.entries)
            ChoiceOption(value: e.key, label: e.value),
        ],
        onChanged: (v) => v == null || controlsLocked
            ? null
            : update(settings.copyWith(stageLayout: v)),
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
        // The address list above already shows the easy name; this
        // row changes it.
        title: const Text('Change easy name'),
        subtitle: Text('${settings.localName}.local'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => changeLocalName(settings),
      ),
      Text(
        deviceText(
          'Guest Wi-Fi often keeps devices apart; phones on it may not reach this phone. If a printed address stops working, the router gave this phone a new one: ask for it to be reserved, or show the join slide instead.',
        ),
        style: TextStyle(color: colors.muted, fontSize: 12, height: 1.4),
      ),
    ];
    final following = <Widget>[
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
              d.role == WebRole.stage ? Icons.tv : Icons.view_list_outlined,
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
    ];
    if (wide) {
      final text = Theme.of(context).textTheme;
      Widget qr(double size) => Container(
        padding: const EdgeInsets.all(10),
        color: Colors.white,
        child: QrImageView(
          key: const ValueKey('web-qr'),
          data: url!,
          size: size,
          backgroundColor: Colors.white,
        ),
      );
      // Flat in its pane: the heading, the QR beside its addresses and
      // codes, buttons of their own size, then the options.
      return KeyedSubtree(
        key: const ValueKey('web-screens'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PaneLabel('Browsers, without the app'),
            const SizedBox(height: 12),
            Text(
              'Web screens',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Any browser on this Wi-Fi (a laptop, TV or phone) can follow the service without the app. Nothing private is shown, and browsers cannot control the service.',
                  style: TextStyle(color: colors.muted, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (url == null)
              Text(
                c.webStageError ?? 'Starting…',
                style: TextStyle(
                  color: c.webStageError == null ? null : colors.warning,
                ),
              )
            else ...[
              LayoutBuilder(
                builder: (context, space) => space.maxWidth >= 500
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          qr(156),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: addresses,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: qr(156),
                          ),
                          const SizedBox(height: 16),
                          ...addresses,
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    'The guest code opens Order of service and stays the same each week, for slides and bulletins. The team code opens Stage display and Service overview too, and changes each time you share.',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                    onPressed: newTeamCode,
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
            const Divider(height: 40),
            const PaneLabel('Web screen options'),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...options],
                ),
              ),
            ),
            ...following,
          ],
        ),
      );
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
              ...addresses,
              Text(
                'The guest code opens Order of service and stays the same each week, for slides and bulletins. The team code opens Stage display and Service overview too, and changes each time you share.',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              // The main action on its own row, the two code changes side by side,
              // instead of three buttons wrapping two and one.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('export-join-slide'),
                    onPressed: () => exportJoinSlide(),
                    icon: const Icon(Icons.slideshow_outlined),
                    label: const Text('Export join slide'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('web-new-codes'),
                          onPressed: newTeamCode,
                          icon: const Icon(Icons.refresh),
                          label: const Text('New team code'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('web-change-order-code'),
                          onPressed: () => changeOrderCode(settings),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Change guest code'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const Divider(height: 28),
            ...options,
            ...following,
          ],
        ),
      ),
    );
  }

  Future<void> exportJoinSlide() async {
    final url = c.webStageUrl;
    if (url == null) return;
    var size =
        joinSlideSizes.where((s) => s.id == lastJoinSlideSize).firstOrNull ??
        joinSlideSizes.first;
    var light = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Export join slide'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pick the screen it will be shown on. The slide is laid out for that shape, not stretched.',
                ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: size.id,
                  onChanged: (v) => update(
                    () => size = joinSlideSizes.firstWhere((s) => s.id == v),
                  ),
                  child: Column(
                    children: [
                      for (final s in joinSlideSizes)
                        RadioListTile<String>(
                          key: ValueKey('slide-size-${s.id}'),
                          contentPadding: EdgeInsets.zero,
                          value: s.id,
                          title: Text('${s.label} · ${s.w} × ${s.h}'),
                          subtitle: Text(s.note),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Dark')),
                    ButtonSegment(
                      value: true,
                      label: Text('Light'),
                      tooltip: 'For projectors that wash out dark slides',
                    ),
                  ],
                  selected: {light},
                  onSelectionChanged: (v) => update(() => light = v.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('slide-export'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    lastJoinSlideSize = size.id;
    try {
      final s = c.webStageSettings;
      final png = await joinSlidePng(
        church: c.state.churchName,
        url: url,
        localUrl: c.webStageLocalUrl,
        code: s.orderAccess == OrderAccess.code ? s.orderCode : null,
        light: light,
        width: size.w,
        height: size.h,
      );
      c.joinSlideAddress = url;
      await c.port.shareFiles([
        SharedFile(
          'Join-the-order-of-service-${size.w}x${size.h}.png',
          png,
          'image/png',
        ),
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
            decoration: InputDecoration(
              helperText: help,
              helperMaxLines: 4,
              errorText: error,
              errorMaxLines: 3,
            ),
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
