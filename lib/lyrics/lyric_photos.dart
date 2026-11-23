import 'dart:convert';

import 'package:flutter/services.dart';

/// The photos that come with the app for slide backgrounds. Each has a
/// CC0 or public-domain entry in assets/lyrics/photos/credits.json, which
/// a test holds this list to.
class LyricPhoto {
  final String id, title, motion;
  const LyricPhoto(this.id, this.title, this.motion);
  String get asset => 'assets/lyrics/photos/$id.jpg';
}

const lyricPhotos = [
  LyricPhoto('waterfall-blue', 'Blue waterfall', 'zoom'),
  LyricPhoto('waterfall-rainbow', 'Waterfall rainbow', 'zoom'),
  LyricPhoto('grass-road-sunrise', 'Morning grass', 'drift'),
  LyricPhoto('milky-way-hills', 'Milky Way', 'zoom'),
  LyricPhoto('joshua-trees-stars', 'Desert stars', 'zoom'),
  LyricPhoto('misty-lake-sunrise', 'Misty lake', 'zoom'),
  LyricPhoto('red-rocks-sunset', 'Red rocks', 'zoom'),
  LyricPhoto('kirkjufell-falls', 'Mountain falls', 'zoom'),
  LyricPhoto('calm-water', 'Calm water', 'zoom'),
  LyricPhoto('deep-sea', 'Deep sea', 'drift'),
  LyricPhoto('northern-lights', 'Northern lights', 'zoom'),
  LyricPhoto('dunes-dusk', 'Dunes at dusk', 'zoom'),
  LyricPhoto('forest-light', 'Forest light', 'zoom'),
  LyricPhoto('mountain-lake', 'Mountain lake', 'zoom'),
  LyricPhoto('golden-sky', 'Golden sky', 'drift'),
  LyricPhoto('candle', 'Candle', 'embers'),
  LyricPhoto('worship-crowd-hands', 'Hands raised', 'zoom'),
  LyricPhoto('sunset-arms-raised', 'Arms raised at sunset', 'zoom'),
  LyricPhoto('hilltop-group-sunset', 'Hilltop at sunset', 'zoom'),
  LyricPhoto('crowd-hands-light-beams', 'Light beams', 'zoom'),
  LyricPhoto('crowd-hands-mono', 'Crowd in black and white', 'zoom'),
  LyricPhoto('beach-silhouette-dusk', 'Beach at dusk', 'drift'),
  LyricPhoto('field-dancer-golden', 'Golden field', 'zoom'),
  LyricPhoto('man-watching-sunset', 'Watching the sunset', 'zoom'),
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
