# Lyrics background photos

The photos that come with the app for lyric slides (Lyrics › Background, under Nature and People). Every one is public domain or CC0, from Wikimedia Commons, at 1920 × 1080; none needs a credit on screen, and they are listed here, and in the app under **Photo credits**, with thanks. The list the app reads is `assets/lyrics/photos/credits.json`; a test checks that every bundled photo has an entry with one of those two licences. The picker shows 320 × 180 copies from `assets/lyrics/photos/thumbs/`.

| Photo | Group | Author | Licence | Source |
|---|---|---|---|---|
| Blue waterfall | Nature | Jason Zhang | CC0 | https://commons.wikimedia.org/wiki/File:Milliken_Park_artificial_waterfall,_June_2018.jpg |
| Rainbow falls | Nature | Sorasak (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Iceland_(Unsplash_8ZAxI5FwjFo).jpg |
| Morning grass | Nature | Daniel Chen (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Tongariro_Holiday_Park_(Unsplash).jpg |
| Milky Way | Nature | NPS/Jacob W. Frank | Public domain | https://commons.wikimedia.org/wiki/File:Milky_Way_and_starry_night_sky_(26972689115).jpg |
| Desert stars | Nature | Joshua Tree National Park | Public domain | https://commons.wikimedia.org/wiki/File:Milky_Way,_Jupiter,_and_night_sky_over_Queen_Valley_(50836084491).jpg |
| Misty lake | Nature | Pseudopanax at English Wikipedia | Public domain | https://commons.wikimedia.org/wiki/File:Calm_Lake_Matheson_with_mist_at_sunrise.jpg |
| Red rocks | Nature | deborah.soltesz | CC0 | https://commons.wikimedia.org/wiki/File:Mitten_Ridge_(Cow_Pies_and_Hangover_Trails)_-_51934836794.jpg |
| Mountain falls | Nature | Steven Diaz (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Kirkjufell,_Iceland_(Unsplash_LoKG7kKx7Zc).jpg |
| Calm water | Nature | Unknown author | CC0 | https://commons.wikimedia.org/wiki/File:Sunset_sky_water.jpg |
| Deep sea | Nature | Tim Marshall (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Ocean_waves_rippling_(Unsplash).jpg |
| Northern lights | Nature | Johannes Groll (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Lofoten,_Norway_(Unsplash).jpg |
| Dunes at dusk | Nature | Joe Mania (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Desert_Dunes_(Unsplash).jpg |
| Forest light | Nature | Steve Redman (MORA) | Public domain | https://commons.wikimedia.org/wiki/File:Sunbeam_through_forest,_Nov_2009._(40971ffd2f2046aea4121cc40616f9b3).JPG |
| Mountain lake | Nature | Lyn Topinka | Public domain | https://commons.wikimedia.org/wiki/File:MSH82_st_helens_spirit_lake_reflection_05-19-82.jpg |
| Golden sky | Nature | Bureau of Land Management Oregon and Washington | Public domain | https://commons.wikimedia.org/wiki/File:Sun_Clouds_(11410891035).jpg |
| Candle | Nature | ViajeroExtraviado | CC0 | https://commons.wikimedia.org/wiki/File:Candle-Vela.jpg |
| Hands raised | People | Bill Hamway (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:2-42_Community_Church,_Brighton_worship_service_(Unsplash).jpg |
| Arms raised | People | Allef Vinicius (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Allef_Vinicius_2017-02-24_(Unsplash).jpg |
| Hilltop sunset | People | Ms.Sue Huan (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:People_Group_Silhouette_Sunset_(Unsplash).jpg |
| Light beams | People | Daniel Robert (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Smoke_and_light_beams_(Unsplash).jpg |
| Crowd, mono | People | Hannah Rodrigo (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Concert_crowd_(Unsplash).jpg |
| Beach at dusk | People | Igor Kasalovic (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Male_silhouette_Sydney_sunset_(Unsplash).jpg |
| Watching sunset | People | Joshua Earle (Unsplash) | CC0 | https://commons.wikimedia.org/wiki/File:Man_watching_Cape_Town_sunset_(Unsplash).jpg |

To add a photo: a JPEG at most 1920 × 1080 and under 750 KB (most are 100 to 450 KB) at `assets/lyrics/photos/<id>.jpg`, a 320 × 180 copy in `thumbs/`, an entry in `credits.json`, and a line in `lib/lyrics/lyric_photos.dart`.
