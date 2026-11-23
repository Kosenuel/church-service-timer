# Lyrics: design note

The feature's user-facing name is **Slides** (the page, the Live button, Commands, **Clear slide**, and the library column, **Library**). Code, files, saved keys and this note keep the working name Lyrics.

Song words, Bible verses and announcements on the second screen, web
screens and stage screens. This note is the plan the feature is built
to, and is kept up to date as it changes. The approved mockup is the
reference for layout, wording and behaviour; the app's theme and
components replace the mockup's own styling.

## Where it lives

- A **Lyrics** page in the navigation, directly after Programs (bottom
  bar, side rail, the desktop tabs in the header, Go to in Commands).
  The page keeps its own number (`lyricsPage = 4`) and is placed third by
  `homePageOrder`, so Live, Programs, Reports and Settings keep 0 to 3 and
  every existing test, key and setting that names them is unchanged.
  Swiping between tabs follows the order on screen.
- A **Lyrics** button on Live opens the same page. In Classic and on a
  phone or tablet it sits beside **Change display** under the display
  preview (stage screens: under the stage preview), and while lyrics are
  on the screens a line says what is showing, with **Clear lyrics**. A
  desktop layout (Three panes, The dial, Mission control, Keys) keeps its
  panes to the window, so the button is an icon in the header there, lit
  while lyrics show, with what is showing in its tooltip; **Clear lyrics**
  is also in Commands (Ctrl+K) whenever lyrics show.
- The page fills the window. At 1100 wide and more it has the mockup's
  three columns (Stored songs, the slides, On the screens now), each
  scrolling on its own. Narrower (phones, tablets upright, small windows)
  it is one column with a bar along the bottom: Previous, Next, Clear
  lyrics and Black stay under the thumb.

## Data model (`lib/domain/lyrics.dart`)

`LyricItem` is one thing in the library:

| Field | Song | Bible verses | Announcement |
|---|---|---|---|
| `id` | random, kept for life | | |
| `kind` | `song` | `scripture` | `announcement` |
| `title` | the song title | the reference, e.g. `John 3:16-18` | the title |
| `words` | the words as typed or pasted | pasted text (custom set) | the body |
| `linesPerSlide` | 0 (as typed), 2 or 4 | | |
| `by` | optional credit line, list only | | |
| `version` | | `KJV`, or what the operator typed (e.g. `NLT`) for pasted text | |
| `verses` | | the looked-up verses `{c, v, t}` | |
| `detail` | | | optional date, time or place line |
| `updated` | wall time of the last save | | |

Looked-up verses are copied into the item, so a saved reading never
depends on a Bible file being present later (and a backup carries it).

`LyricSlide` is what one slide shows: `label` (Verse 1, Chorus, Slide 3,
John 3:16-17), `text`, and for verses a `reference` line ("John 3:16 ·
KJV"), for announcements `title` and `detail`. Slides are worked out
from the item every time (`LyricItem.slides`), never saved.

### Song words to slides (`parseSongSlides`)

- Windows (`\r\n`) and old Mac (`\r`) line endings, tabs, non-breaking
  and zero-width spaces are normalised; each line is trimmed; a line of
  spaces is blank.
- A blank line starts a new slide.
- A heading line (Verse, Verse 1, Chorus, Refrain, Bridge, Pre-chorus,
  Intro, Outro, Tag, Ending, optionally numbered, in brackets or followed
  by a colon or full stop) names the slide and is not shown. A heading in
  the middle of a block starts a new slide too, and a heading on its own
  names the slide after it.
- **Lines on a slide**: As typed keeps each block whole; 2 or 4 splits a
  block into slides of that many lines, each keeping the block's name.
- A slide with no heading is "Slide N".

### Bible verses (`lib/domain/bible.dart`)

- The King James Version (1769 text, public domain) is bundled as
  `assets/bible/kjv.txt.gz` (about 1.4 MB). Format, one UTF-8 line each:
  a header `CSTBIBLE 1|KJV|King James Version (1769)|Public domain`, then
  `#Book name` before each book, `@` before each chapter and one verse
  per line. Other translations can be added in phase 2 as downloaded
  files in the same format in the app's data folder; `BibleLibrary`
  already lists translations by code, and the lookup takes the code.
- Source: `aruljohn/Bible-kjv` (MIT for the files; the text is the
  public-domain KJV), fetched from
  `https://raw.githubusercontent.com/aruljohn/Bible-kjv/master/<Book>.json`
  on 23 November 2026. Checked: 66 books, 31,102 verses; compared with two
  other public KJV files (`thiagobodruk/bible` `en_kjv.json` and
  `scrollmapper/bible_databases` `KJV.json`): this one keeps "LORD" in
  small capitals as LORD, the 1769 punctuation ("without form, and
  void") and spellings ("instructer"), and has no stray spaces before
  punctuation, which the others had. Trailing spaces were trimmed.
- References: `John 3:16`, `John 3:16-18`, `John 3:16–4:2`, `Psalm 23`,
  `Ps 23:1-3`, `1 Cor 13:4-7`, `1Co 13`, `First Corinthians 13`, `Song of
  Songs 2`, `Jn 3 16`. Book names and common abbreviations are matched
  without case or full stops. Bad input gets a message that says what to
  fix ("There is no chapter 40 in John: it has 21.", "Try a book and
  chapter, such as John 3 or Psalm 23.").
- Slides: one or more verses per slide, fitted by length (about 280
  characters, never splitting a verse unless one alone is very long,
  when it is split at a sentence or clause). Verse numbers are small
  superscripts when a slide has more than one verse. The reference line
  under the text names that slide's verses: "John 3:16-17 · KJV".
- No copyrighted translation is bundled (the NLT belongs to Tyndale).
  **Paste your own** takes any text with its own reference line, split
  into slides at blank lines and by length.

### Announcements

A title, a body and an optional detail line (date, time, place), as one
designed slide: the title large in the accent colour, the body under it,
the detail line smaller, left or centre aligned as the screen look says,
on the same backgrounds. Saved in the library like songs.

## Where state is saved

`AppState.lyrics` (`LyricsLibrary`, saved key `lyrics`):

- `lastUsed`: item id to the wall time it was last put on the screens;
  ordering state, kept apart from the item records.
- `items`: the library (at most 300 items), shown in the left column as
  **Stored songs**: every stored song, Bible passage set and announcement,
  searchable by title and words, most recently used first (then most
  recently saved).
- `look`: the screen look: `background` (default `mountain_dusk`),
  `dim` (0 to 90, default 70), `size` (`s`, `m`, `l`), `align`
  (`center`, `left`), `chip` (countdown in the corner, default on),
  `motion` (`gentle` or `still`), and Send to: `second` (on), `web` (on),
  `stage` (**off**).

A missing `lyrics` key reads as an empty library with the default look,
so saved data from before this feature loads unchanged; the saved-state
version stays 16, so earlier versions ignore the key.

Backups (`exportBackup`) carry `lyrics` (items and look) when the
library has anything in it, as schema version 12; plain backups stay
version 11 or lower and readable by earlier versions. "Your picture" is
not in backups: it is a file on this device (see below), and a restored
look that named one falls back to Midnight.

What is showing now (the item, the slide, Black) is kept in memory only
(`LyricsController`): it is not saved, so a restart starts with no
lyrics on the screens. Ending a service leaves the library and the slide on the screens as they are; lyrics can be shown
with no service at all.

## Snapshots

A new optional field, `lyrics`, is added to the picture each kind of
screen gets, only for the screens ticked under **Send to**:

| Send to | Gets `lyrics` |
|---|---|
| Second screen (phone/tablet: **This screen**) | the second screen window, its copy on Live, host full screen, the stage simulator |
| Web screens | web Stage displays (`/api/state`, stage role only) |
| Stage screens | paired phones and tablets showing the stage |

The LED sign never gets it, and the countdown and every other field are
still sent as before. The field:

```json
"lyrics": {
  "v": 1, "key": "<item>:<slide>:<black>", "kind": "song",
  "label": "Verse 2", "text": "...", "reference": "", "title": "", "detail": "",
  "bg": "mountain_dusk", "dim": 70, "size": "m", "align": "center",
  "motion": true, "chip": "12:34", "chipOver": false
}
```

`black: true` replaces the slide fields while Black is on. `chip` is the
time left, only while a service runs and the countdown chip is on.
`bg` is a drawn design's id, `photo:<id>` for a bundled photo, or
`custom:<name>` for "Your picture"; the second screen also gets
`picture`, the file's path on this computer.

`StageSurface` has one hook: when `lyrics` is present and no quick
message is showing, it draws `LyricStage` (`lib/lyrics/lyric_stage.dart`)
instead of the countdown. A quick message to a stage screen still wins,
so the speaker always sees it. An older paired phone or web page does
not know the field and keeps showing the countdown, as if Stage screens
were unticked. **Clear lyrics** removes the field, so every screen goes
back to exactly what it would show without lyrics: the countdown, the
clock, a cue, the end screen or black.

## Rendering (`lib/lyrics/`)

- `LyricStage`: background, then the Dim layer (black at `dim`%, not on
  Linen, whose words are dark), then the words, then the countdown chip.
  Words are white with a soft shadow on dark backgrounds and near-black
  on Linen. The size is the largest that fits (S, M or L sets the most it
  may be), found by measuring: every line fits across without a word
  being broken and the whole fits the height. Each typed line stays one
  line when that costs at most a fifth of the size; otherwise a long line
  wraps into lines of nearly equal length. Verse numbers are drawn as
  small gold digits (Roboto has no raised 4 to 9). Nothing is clipped
  or scaled out of shape. Slides cross-fade, except with reduced motion.
- The same sizing in the web page's script, measured in the browser.
- The picker groups them as Designs (12), Nature (16), People (7) and
  Your picture, and shows the small copies, never decoding full HD.
- `lyric_backgrounds.dart`: the twelve drawn designs as painters, drawn
  from the mockup's shapes on a 160 × 90 grid and stretched to the
  screen, and the web page draws the same shapes on a canvas. Gentle
  motion: slow zoom, drift, colour shimmer, twinkling stars, rising
  embers. Off with Still, with the app's Reduced motion, and in the
  browser with the system's reduced motion.

## Pictures on screens

- **Bundled photos**: 23 (`assets/lyrics/photos/*.jpg`, 1920 × 1080 at
  JPEG quality 80, about 6.5 MB in all with their 320 × 180 picker copies
  in `thumbs/`, from the photo research set; 16 under Nature and 7 under
  People, in silhouette or from behind), each with a CC0 or public-domain entry in
  `assets/lyrics/photos/credits.json`, listed in the app under
  Lyrics › Background › Photo credits and in `docs/LYRICS-PHOTOS.md`).
  Screens get them by name: paired phones and the second screen have the
  same files; web screens fetch `/lyrics/photo?id=…` from the host.
- **Your picture**: picked with the same picker as the church logo
  (Android's document picker, the Windows file window), made upright and
  at most 1600 px on its longer side, and kept in the app's data folder
  (`lyric-picture.jpg`; one at a time). It reaches the second screen (by
  its path on the same computer), host full screen, the simulator and
  web screens (`/lyrics/picture` on the host). It is **not sent to paired
  stage screens in phase 1**: they show Midnight instead, and the panel
  says so under the background picker.

## Keys

On the Lyrics page, while no text field has the keyboard and no window
is open on top: **→**, **Space** or **Page Down** next slide; **←** or
**Page Up** previous; **Esc** clear lyrics; **B** black (again to bring
the slide back). Live's own meanings of Space, B and → (pause and next
segment) apply only on Live, so they never clash: on the Lyrics page
those keys never touch the timer, and on Live they never change a slide.
The page shows its keys in the line under the slides.

## Phase split

Phase 1 (this branch):

1. The operator panel, as in the mockup, on desktop and phone.
2. Add and edit a song (**Save song**), open a .txt file, delete with
   confirmation.
3. Bible verses: the bundled KJV, references, paste your own.
4. Announcements.
5. The slide on every screen, including the web page.
6. Twelve drawn backgrounds, bundled photos, Your picture.
7. Clear lyrics restores each screen; the library survives.

Phase 2 (not this branch):

- Background videos: three bundled loops, **Find more videos** (opens
  known free-video sites in the browser) and adding your own video
  file; Still pauses them. Needs a video player on Windows and Android
  and a way to reach web screens (served from the host like photos).
- Downloading more public-domain Bible translations (e.g. ASV, WEB) as
  files in the `CSTBIBLE` format into the app's data folder; the
  reference box gets a translation choice.
- Your picture on paired stage screens (sent once over the pairing
  connection, cached by name).
- **Songs attached to program segments** (the agreed next step): a
  segment in a program carries an ordered list of library item ids
  (e.g. "Praise & Worship: Amazing Grace, Holy, Holy, Holy"), and when
  that segment starts its items are lined up on the Lyrics page. Phase 1
  is shaped for it: every library item has a stable `id` that never
  changes when it is edited, and the library records hold only what the
  item is. Ordering and selection live apart from them: `lastUsed` (id to
  wall time) orders Stored songs, and what is selected or on the screens
  is in `LyricsController`. A segment's list would be a list of ids kept
  in the program, read against the library (an id no longer in the
  library is skipped). No UI or saved field for it yet.
