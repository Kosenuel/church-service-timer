/// The photos that come with the app for slide backgrounds. Each has a
/// CC0 or public-domain entry in assets/lyrics/photos/credits.json, which
/// a test holds this list to.
class LyricPhoto {
  final String id, title, motion;
  const LyricPhoto(this.id, this.title, this.motion);
  String get asset => 'assets/lyrics/photos/$id.jpg';
}

const lyricPhotos = [
  LyricPhoto('calm-water', 'Calm water', 'zoom'),
  LyricPhoto('deep-sea', 'Deep sea', 'drift'),
  LyricPhoto('northern-lights', 'Northern lights', 'zoom'),
  LyricPhoto('dunes-dusk', 'Dunes at dusk', 'zoom'),
  LyricPhoto('forest-light', 'Forest light', 'zoom'),
  LyricPhoto('mountain-lake', 'Mountain lake', 'zoom'),
  LyricPhoto('golden-sky', 'Golden sky', 'drift'),
  LyricPhoto('candle', 'Candle', 'embers'),
];

final lyricPhotoIds = {for (final p in lyricPhotos) p.id};

LyricPhoto? lyricPhotoById(String id) {
  for (final p in lyricPhotos) {
    if (p.id == id) return p;
  }
  return null;
}
