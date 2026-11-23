# Lyrics background photos

The photos that come with the app for lyric slides (Lyrics › Background). Every one is public domain or CC0, from Wikimedia Commons; none needs a credit on screen, and they are listed here, and in the app under **Photo credits**, with thanks. The list the app reads is `assets/lyrics/photos/credits.json`; a test checks that every bundled photo has an entry with one of those two licences.

| Photo | Author | Licence | Source |
|---|---|---|---|
| Calm water | Unknown author | CC0 | https://commons.wikimedia.org/wiki/File:Sunset_sky_water.jpg |
| Deep sea | Tim Marshall (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Ocean_waves_rippling_(Unsplash).jpg |
| Northern lights | Johannes Groll (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Lofoten,_Norway_(Unsplash).jpg |
| Dunes at dusk | Joe Mania (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Desert_Dunes_(Unsplash).jpg |
| Forest light | Steve Redman (MORA) | Public domain | https://commons.wikimedia.org/wiki/File:Sunbeam_through_forest,_Nov_2009._(40971ffd2f2046aea4121cc40616f9b3).JPG |
| Mountain lake | Lyn Topinka (USGS) | Public domain | https://commons.wikimedia.org/wiki/File:MSH82_st_helens_spirit_lake_reflection_05-19-82.jpg |
| Golden sky | A Flickr contributor (named on the source page) | Public domain | https://commons.wikimedia.org/wiki/File:Sun_Clouds_(11410891035).jpg |
| Candle | ViajeroExtraviado | CC0 | https://commons.wikimedia.org/wiki/File:Candle-Vela.jpg |

To add a photo: a JPEG at most 1920 × 1080 and under 600 KB, at `assets/lyrics/photos/<id>.jpg`, an entry in `credits.json`, and a line in `lib/lyrics/lyric_photos.dart`.
