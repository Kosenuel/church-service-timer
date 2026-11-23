import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';

class PairQrDialog extends StatefulWidget {
  final PairHub hub;
  const PairQrDialog({super.key, required this.hub});
  @override
  State<PairQrDialog> createState() => _PairQrDialogState();
}

class _PairQrDialogState extends State<PairQrDialog> {
  Timer? timer;
  bool closing = false;
  late Set<PairPeer> existing;
  @override
  void initState() {
    super.initState();
    existing = widget.hub.peers.toSet();
    widget.hub.addListener(refresh);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void refresh() {
    final pending = widget.hub.peers
        .where(
          (p) =>
              !existing.contains(p) &&
              !p.approved &&
              !p.wire.closed &&
              !p.suspended,
        )
        .firstOrNull;
    if (mounted && !closing && pending != null) {
      closing = true;
      final navigator = Navigator.of(context), hub = widget.hub;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !navigator.mounted) return;
        navigator.pop();
        final approve = await showDialog<bool>(
          context: navigator.context,
          builder: (ctx) => AlertDialog(
            title: const Text('Approve paired device?'),
            content: Text(
              '${pending.name}\n${pending.role == 'operator' ? 'Operator · control requires a separate handover' : 'Stage / service viewer'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Approve'),
              ),
            ],
          ),
        );
        if (!hub.hosting || pending.wire.closed || !hub.peers.contains(pending))
          return;
        try {
          if (approve == true) await hub.approve(pending);
          if (approve == false) await hub.forgetDevice(pending.id);
        } catch (_) {
          if (navigator.mounted)
            ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
              const SnackBar(
                content: Text(
                  'Device unavailable. Review the paired devices list.',
                ),
              ),
            );
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.hub.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invitation = widget.hub.code;
    final valid =
        invitation != null &&
        invitation.expires > DateTime.now().millisecondsSinceEpoch;
    return AlertDialog(
      title: const Text('Pair with QR code'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (valid)
                QrImageView(
                  data: invitation.encode(),
                  size: 250,
                  backgroundColor: Colors.white,
                  semanticsLabel:
                      'Private pairing invitation. Scan from the second device.',
                )
              else
                const Text('This invitation expired. Generate a new code.'),
              const SizedBox(height: 12),
              const Text(
                'On the second device, choose Scan QR code instead. Keep this invitation private; it expires after 10 minutes. You still approve the device.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.hub.hosting ? widget.hub.newCode : null,
          child: const Text('New code'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class PairScannerPage extends StatefulWidget {
  const PairScannerPage({super.key});
  @override
  State<PairScannerPage> createState() => _PairScannerPageState();
}

class _PairScannerPageState extends State<PairScannerPage> {
  final scanner = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool done = false;
  String? error;
  @override
  void dispose() {
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: finishBar(context),
      title: const Text('Scan host QR code'),
    ),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: scanner,
            onDetect: (capture) {
              if (done || !mounted) return;
              final raw = capture.barcodes.firstOrNull?.rawValue;
              try {
                PairCode.parse(raw ?? '');
                done = true;
                Navigator.pop(context, raw);
              } catch (_) {
                setState(
                  () => error =
                      'Use a current Church Service Timer QR code from the host.',
                );
              }
            },
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable. Allow camera access in Android settings, or go back and enter the six-digit code.',
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            error ?? 'Point the camera at the QR code on the host device.',
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Use six-digit code instead'),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}
