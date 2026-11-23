import 'dart:convert';

import 'package:flutter/services.dart';

/// The photos that come with the app for slide backgrounds. Each has a
/// CC0 or public-domain entry in assets/lyrics/photos/credits.json, which
/// a test holds this list to.
class LyricPhoto {
  final String id, title, motion;

  /// `nature` or `people`, the picker's groups.
  final String kind;
  const LyricPhoto(this.id, this.title, this.motion, this.kind);
  String get asset => 'assets/lyrics/photos/$id.jpg';

  /// A 320 × 180 copy for the picker, so it never decodes full HD.
  String get thumbnail => 'assets/lyrics/photos/thumbs/$id.jpg';
}

const lyricPhotos = [
  LyricPhoto('waterfall-blue', 'Blue waterfall', 'zoom', 'nature'),
  LyricPhoto('waterfall-rainbow', 'Rainbow falls', 'zoom', 'nature'),
  LyricPhoto('grass-road-sunrise', 'Morning grass', 'drift', 'nature'),
  LyricPhoto('milky-way-hills', 'Milky Way', 'zoom', 'nature'),
  LyricPhoto('joshua-trees-stars', 'Desert stars', 'zoom', 'nature'),
  LyricPhoto('misty-lake-sunrise', 'Misty lake', 'zoom', 'nature'),
  LyricPhoto('red-rocks-sunset', 'Red rocks', 'zoom', 'nature'),
  LyricPhoto('kirkjufell-falls', 'Mountain falls', 'zoom', 'nature'),
  LyricPhoto('calm-water', 'Calm water', 'zoom', 'nature'),
  LyricPhoto('deep-sea', 'Deep sea', 'drift', 'nature'),
  LyricPhoto('northern-lights', 'Northern lights', 'zoom', 'nature'),
  LyricPhoto('dunes-dusk', 'Dunes at dusk', 'zoom', 'nature'),
  LyricPhoto('forest-light', 'Forest light', 'zoom', 'nature'),
  LyricPhoto('mountain-lake', 'Mountain lake', 'zoom', 'nature'),
  LyricPhoto('golden-sky', 'Golden sky', 'drift', 'nature'),
  LyricPhoto('candle', 'Candle', 'embers', 'nature'),
  LyricPhoto('worship-crowd-hands', 'Hands raised', 'zoom', 'people'),
  LyricPhoto('sunset-arms-raised', 'Arms raised', 'zoom', 'people'),
  LyricPhoto('hilltop-group-sunset', 'Hilltop sunset', 'zoom', 'people'),
  LyricPhoto('crowd-hands-light-beams', 'Light beams', 'zoom', 'people'),
  LyricPhoto('crowd-hands-mono', 'Crowd, mono', 'zoom', 'people'),
  LyricPhoto('beach-silhouette-dusk', 'Beach at dusk', 'drift', 'people'),
  LyricPhoto('man-watching-sunset', 'Watching sunset', 'zoom', 'people'),
];

final lyricPhotoIds = {for (final p in lyricPhotos) p.id};

LyricPhoto? lyricPhotoById(String id) {
  for (final p in lyricPhotos) {
    if (p.id == id) return p;
  }
  return null;
}

/// The credits for the bundled photos, from assets/lyrics/photos/credits.json.
Future<List<Map<String, dynamic>>> lyricPhotoCredits() async {
  final raw = await rootBundle.loadString('assets/lyrics/photos/credits.json');
  return [
    for (final e in jsonDecode(raw) as List)
      Map<String, dynamic>.from(e as Map),
  ];
}
