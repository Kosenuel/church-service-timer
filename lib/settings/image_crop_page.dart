import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter/material.dart';

/// Crops a photo to a fixed shape: drag to move, pinch to zoom, like
/// setting a profile picture. The frame keeps the [width]:[height] ratio
/// and the photo always covers it, so the result has no empty edges.
/// Returns a [width] × [height] PNG as base64, or null.
class ImageCropPage extends StatefulWidget {
  /// The decoded photo; the page disposes of it when it closes.
  final ui.Image photo;
  final int width, height;
  final String title, hint, action;
  const ImageCropPage({
    super.key,
    required this.photo,
    required this.width,
    required this.height,
    required this.title,
    required this.hint,
    required this.action,
  });

  /// The church logo: square, [churchLogoSize] pixels.
  static Future<String?> logo(BuildContext context, Uint8List photo) => _open(
    context,
    photo,
    (image) => ImageCropPage(
      photo: image,
      width: churchLogoSize,
      height: churchLogoSize,
      title: 'Crop logo',
      hint:
          'The logo is square. Drag to move and pinch to zoom until it fills the square the way you want.',
      action: 'Use logo',
    ),
  );

  /// The church banner: 3:1, 600 × 200 pixels.
  static Future<String?> banner(BuildContext context, Uint8List photo) => _open(
    context,
    photo,
    (image) => ImageCropPage(
      photo: image,
      width: 600,
      height: 200,
      title: 'Crop banner',
      hint:
          'The banner is three times as wide as it is tall. Drag to move and pinch to zoom until it frames what you want.',
      action: 'Use banner',
    ),
  );

  /// Decodes the photo first, so the page opens with it ready and a file
  /// that cannot be read fails here, before anything is shown.
  static Future<String?> _open(
    BuildContext context,
    Uint8List photo,
    ImageCropPage Function(ui.Image image) page,
  ) async {
    final codec = await ui.instantiateImageCodec(photo);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    if (!context.mounted) {
      image.dispose();
      return null;
    }
    return Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => page(image)),
    );
  }

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  String? problem;
  bool saving = false;
  final transform = TransformationController();
  Size frame = Size.zero;
  double cover = 1;
  double get aspect => widget.width / widget.height;

  late final ui.Image image = widget.photo;

  @override
  void dispose() {
    transform.dispose();
    image.dispose();
    super.dispose();
  }

  /// Fits the photo so it covers the frame, centred.
  void fit(Size size) {
    final i = image;
    if (size == frame) return;
    final first = frame == Size.zero;
    frame = size;
    cover = math.max(size.width / i.width, size.height / i.height);
    final dx = (size.width - i.width * cover) / 2,
        dy = (size.height - i.height * cover) / 2;
    final value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(cover, cover, 1, 1);
    // The first fit happens before the viewer listens; after a rotation
    // the viewer is listening, so wait until the frame is built.
    if (first) {
      transform.value = value;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) transform.value = value;
      });
    }
  }

  /// The part of the photo inside the frame, in photo pixels.
  Rect visible() {
    final m = transform.value;
    final scale = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final i = image;
    final w = math.min(
      frame.width / scale,
      math.min(i.width.toDouble(), i.height * aspect),
    );
    final h = w / aspect;
    final left = (-t.x / scale).clamp(0.0, i.width - w);
    final top = (-t.y / scale).clamp(0.0, i.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  Future<void> useImage() async {
    setState(() => saving = true);
    try {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        visible(),
        Rect.fromLTWH(0, 0, widget.width.toDouble(), widget.height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(widget.width, widget.height);
      picture.dispose();
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (mounted) {
        Navigator.pop(context, base64Encode(data!.buffer.asUint8List()));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          problem = 'This photo could not be cropped. Try another one.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.title),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = math.max(
                  120.0,
                  math.min(box.maxWidth - 48, (box.maxHeight - 24) * aspect),
                );
                final size = Size(width, width / aspect);
                fit(size);
                return Center(
                  child: SizedBox.fromSize(
                    key: const ValueKey('image-crop-frame'),
                    size: size,
                    child: Stack(
                      children: [
                        ClipRect(
                          child: InteractiveViewer(
                            transformationController: transform,
                            constrained: false,
                            boundaryMargin: EdgeInsets.zero,
                            minScale: cover,
                            maxScale: cover * 8,
                            child: RawImage(
                              image: image,
                              width: image.width.toDouble(),
                              height: image.height.toDouble(),
                            ),
                          ),
                        ),
                        // The frame's edge and thirds, like a camera grid.
                        IgnorePointer(
                          child: CustomPaint(size: size, painter: _CropGrid()),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                problem!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('use-cropped-image'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: saving ? null : useImage,
                    child: Text(saving ? 'Preparing…' : widget.action),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CropGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * f, 0),
        Offset(size.width * f, size.height),
        line,
      );
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        line,
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropGrid oldDelegate) => false;
}
