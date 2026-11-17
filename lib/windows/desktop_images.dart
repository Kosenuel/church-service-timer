import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// The desktop counterpart of ChurchBanner.kt: private, metadata-free copies
// of a picked picture. The original file is never changed.

bool _isSupportedImage(Uint8List b) {
  bool starts(List<int> magic, [int at = 0]) {
    if (b.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[at + i] != magic[i]) return false;
    }
    return true;
  }

  return starts([0xff, 0xd8, 0xff]) || // JPEG
      starts([0x89, 0x50, 0x4e, 0x47]) || // PNG
      (starts([0x52, 0x49, 0x46, 0x46]) &&
          starts([0x57, 0x45, 0x42, 0x50], 8)); // WebP
}

/// Checks and decodes the picked image, upright, at most 2400 px on its
/// longer side.
Future<ui.Image> _decodeUpright(Uint8List raw) async {
  require(raw.length <= 5000000, 'Choose an image no larger than 5 MB.');
  require(_isSupportedImage(raw), 'Choose a JPEG, PNG or WebP image.');
  final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
  final ui.ImageDescriptor descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    buffer.dispose();
    throw RuleError('This image could not be decoded.');
  }
  try {
    final w = descriptor.width, h = descriptor.height;
    require(
      w > 0 && h > 0 && w * h <= 40000000,
      'Choose an image up to 40 megapixels.',
    );
    var sample = 1;
    while (math.max(w, h) / sample > 2400) {
      sample *= 2;
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: sample == 1 ? null : math.max(1, w ~/ sample),
      targetHeight: sample == 1 ? null : math.max(1, h ~/ sample),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (e) {
    if (e is RuleError) rethrow;
    throw RuleError('This image could not be decoded.');
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

Future<ui.Image> _draw(ui.Image source, int width, int height, ui.Rect to) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    to,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

/// Uniform scale then centred crop into 600 × 200; neither axis is
/// stretched on its own. Same arithmetic as BannerFrame.kt.
ui.Rect bannerFrame(int width, int height) {
  require(width > 0 && height > 0, 'This image could not be decoded.');
  final scale = math.max(600 / width, 200 / height);
  final w = width * scale, h = height * scale;
  return ui.Rect.fromLTRB(
    (600 - w) / 2,
    (200 - h) / 2,
    (600 + w) / 2,
    (200 + h) / 2,
  );
}

/// The church banner: a 600 × 200 PNG, as base64.
Future<String> churchBannerFrom(Uint8List raw) async {
  final image = await _decodeUpright(raw);
  try {
    final banner = await _draw(
      image,
      600,
      200,
      bannerFrame(image.width, image.height),
    );
    try {
      final png = await banner.toByteData(format: ui.ImageByteFormat.png);
      require(png != null, 'Could not prepare banner.');
      require(
        png!.lengthInBytes <= 500000,
        'Image could not be reduced to the banner size.',
      );
      return base64Encode(png.buffer.asUint8List());
    } finally {
      banner.dispose();
    }
  } finally {
    image.dispose();
  }
}

Uint8List _jpeg((Uint8List rgba, int width, int height) job) => img.encodeJpg(
  img.Image.fromBytes(
    width: job.$2,
    height: job.$3,
    bytes: job.$1.buffer,
    numChannels: 4,
  ),
  quality: 92,
);

/// A copy for the church logo: at most 1600 px on its longer side, PNG
/// when the picture has transparency (so a logo on a clear background is
/// not turned black) and JPEG otherwise, as base64. The square crop is
/// done in the app.
Future<String> churchPhotoFrom(Uint8List raw) async {
  final image = await _decodeUpright(raw);
  ui.Image? scaled;
  try {
    final longest = math.max(image.width, image.height);
    var output = image;
    if (longest > 1600) {
      final factor = 1600 / longest;
      final w = math.max(1, (image.width * factor).toInt());
      final h = math.max(1, (image.height * factor).toInt());
      output = scaled = await _draw(
        image,
        w,
        h,
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      );
    }
    final pixels = await output.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    require(pixels != null, 'Could not prepare the photo.');
    final rgba = pixels!.buffer.asUint8List();
    var transparent = false;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) {
        transparent = true;
        break;
      }
    }
    if (transparent) {
      final png = await output.toByteData(format: ui.ImageByteFormat.png);
      require(png != null, 'Could not prepare the photo.');
      return base64Encode(png!.buffer.asUint8List());
    }
    return base64Encode(
      await compute(_jpeg, (rgba, output.width, output.height)),
    );
  } finally {
    scaled?.dispose();
    image.dispose();
  }
}
