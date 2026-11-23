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

## The Slides page (layout)

The page was tidied so the output pane stays calm and the four buttons
never scroll out of reach (`lib/lyrics/slides_parts.dart` holds the
pieces laid out on their own).

- **Library** (left, 328 wide): the search box, then four tabs by their
  full names, **Songs**, **Bible verses**, **Announcements** and **All**
  (`AppState.slidesTab`, default All so nothing in an existing library
  is hidden). The tabs share the leftover width round their names; when
  the names do not fit (a phone, large text) the row scrolls sideways
  instead of squeezing or cutting a name. While searching, the tabs go
  and the search covers every kind. Each tab has its own empty line. The
  three Add buttons are one quiet row pinned to the bottom of the card
  (**+ Song**, **+ Bible verses**, **+ Announcement**); only when the
  full words do not fit on one row do they become + Song, + Verses and
  + Notice, and only if those do not fit either do they wrap. Their
  tooltips and screen-reader names always say the whole thing.
- **Slides** (middle): the Ready tray, the item's title with its list
  line under it and Edit, the slide grid, and the keys as one quiet line
  under it (on a touch screen, "Tap a slide to show it").
- **On the screens now** (right; on a phone the preview card, the rows
  card and the bar along the bottom): the preview; a one-line status
  (`maxLines: 1`, never wrapped: "Amazing Grace · Verse 2 · 2 of 4",
  "Psalm 23:1-3", "Black on the screens", with "· on no screen" when
  no screen is chosen); one row of **Previous**, **Next** (widest,
  filled), **Clear** and **Black** (black while on). The four never
  wrap: the keys under the words are dropped first, then the four words
  shrink together (to at most 60%, then a FittedBox). Then three rows
  with hairlines between:
  - **Screens**: the chosen targets as text and **Change**, which opens
    the existing Send to chips and note in place (not remembered). The
    send-to state and logic are unchanged. "The second screen is not
    showing" stays visible with the row closed.
  - **Background**: a swatch, the background's name and a chevron; opens
    to the picker with a chip for each group (Designs, Nature, People,
    Your picture; the current background's group first), the tiles, the
    note and Photo credits.
  - **Look**: a summary built from the look ("Dim 70% · Medium · Centre
    · Gentle · Countdown", "Not dimmed" on Linen); opens to Dim, Text
    size, Align, Motion and Countdown in the corner (now a switch).
  In a narrow card the value goes under the row's name.
- Background and Look start closed; which are open is
  `AppState.slidesOpen` (`background`, `look`). Both it and the tab are
  kept on this device only, like `dismissedHints`: removed in
  `exportBackup`, untouched by a restore, and a missing or unknown value
  reads as the default. The panel keeps its own copy, so a tap shows at
  once even while a save is under way, and saves after it.
- Keys: each row's header is one focusable button (Tab reaches it) that
  a screen reader hears as expanded or collapsed. Enter opens and
  closes it; Space does too while the header has the keyboard
  (`slidesFoldHasFocus`), and moves to the next slide everywhere else.
  The arrows, Esc, B, / and Ctrl+F work as before.

### Emphasis marks in pasted words

Words pasted from lyrics sites, chat apps and notes apps carry Markdown
or WhatsApp emphasis: `_(x2)_` (italic), `**Chorus**` (bold). The app
has no emphasis syntax of its own, so the marks were printed on the
cards, the preview and every screen. `lyricShownLine` takes a pair of
`_`, `__`, `*` or `**` off round words when the slides are made (song
lines before the heading check, so `_Chorus_` names a slide; an
announcement's title and words; pasted Bible text). A lone mark, one
inside a word (`snake_case`) or a sum (`2*3*4`) stays. The saved words
keep exactly what was typed. Since screens get the slide's text from the
host, the second screen, paired screens, web screens, full screen and
the simulator all show it the same way, whatever version they run.

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
The page shows its keys in the line under the slides, and under the
words of each of the four buttons on a computer. Space on a focused row
that folds open opens or closes it instead (see The Slides page).

## Scripture search and the Ready tray

A search box on the Slides page finds verses as the operator types, by
reference or by words, entirely on the device, and puts a verse on the
screens in one or two taps. Code: `lib/domain/bible_search.dart` (the
index and the search, plain Dart), `lib/lyrics/scripture_search*.dart`
(the box, its results, the phone sheet) and `lib/lyrics/ready_tray.dart`.

### One box or two

One box. The box at the top of **Library** searches the Library and the
Bible together, because mid-service the operator knows what they want,
not which shelf it is on: "amazing" and "john 3 16" go in the same place.
Results are grouped, **Library** then **Bible**; when the text reads as a
reference the Bible comes first and the Library group (if anything in it
matches) follows. At most four Library lines show, with "Show all N".
While a search is under way the Library column grows from 280 to 400
wide so verses read on a few lines, and the library list is replaced by
the results; Esc (or the clear button) brings the list back. The phone's
Library sheet (the picker under the preview) keeps its old Library-only
box.

### The index

Built from the parsed `Bible` (so from any translation in the
`CSTBIBLE` format; `BibleSearchIndex.build(bible)` knows nothing else
about a translation, and a result is a passage by book, chapter and verse,
so it can be shown in another translation later). Tables, all typed
lists: each verse's words as small numbers (about 790,000 words), for
each distinct word the verses that have it, a sorted list of the words as
spelt (for typing the start of a word and for typos), and a book, chapter
and verse number per verse. It holds about 6.6 MB in memory for the KJV
beyond the Bible text itself, counted from the sizes of those tables, and
nothing is added to the app download: it is built at run time from the
bundled `kjv.txt.gz`.

`ScriptureIndex.load()` reads the asset on the main isolate and does the
unzipping, parsing and indexing in `Isolate.run`, the first time the
Slides page opens (so it is ready by the first keystroke), then keeps it
for the session; the parsed Bible is handed to `BibleLibrary` so verses
are not parsed twice. While it builds the box says "Preparing search…"
and finishes the search by itself when the index arrives. It is not
cached on disk: building takes about a second, and a cache file would have
to be kept in step with the Bible file. Numbers are in the test output
(`test/domain/bible_search_test.dart`); see the pull request.

### What a search does

1. **A reference** (`interpretReference`, the one place that calls
   `parseBibleReference`, `bibleBookOf` and `bibleBookGuesses`; it reads
   misspelt books, "john 3 v 9", spoken numbers, and shows "Showing John
   3:16" when a spelling was corrected; a book that could be several
   becomes the chips): `John 3:16`, `john 3 16`,
   `joh 3`, `1cor13 4-7`, `psalm 23`, ranges and cross-chapter ranges.
   A chapter shows the whole chapter first and then each verse; a lone
   verse number narrows as it is typed (`john 3:1` shows 1 and 10 to 19,
   `john 3:16` shows 16); a range is one passage. A trailing `:` or `-`
   (still typing) is ignored. A bad reference says what is wrong, in the
   words the editor uses ("There is no chapter 40 in John: it has 21
   chapters."). The start of a book's name offers the books as chips, in
   alphabetical order (`jo`: Job, Joel, John, Jonah, Joshua); tapping one
   completes the box.
2. **A name** such as "the Lord's Prayer" or "the Beatitudes" (a table of
   23, `namedPassages`) puts that passage first.
3. **Words**, in any order. The last word is a prefix while the operator
   is still typing (until they type a space). Words in quotes must be
   next to each other in that order. A word that is nowhere is set aside
   with a note ("No verse has “xyzzy”; showing the rest of your words.")
   as long as another real word matches. A word that is not in the
   Bible but is a letter or two away (one slip from four letters, two
   from eight; a swap of two letters counts as one) matches the nearest
   words. Common words are not dropped but weigh a quarter as much, so
   "in the beginning" works; a query of nothing but common words
   finds nothing (too many verses to be of any use).
4. **A book first narrows**: `rom faith` searches Romans only. This is how
   Old Testament, New Testament and a single book are chosen; there are no
   extra controls. It applies when the first words are a whole book name
   or a short form that is not also a common word in the verses (so "the"
   does not mean Thessalonians), and when nothing is found inside the
   book the words are searched everywhere ("mark my words").

Ranking, best first, and within each by weight, then canonical order:
the reference; a named passage; the words as an exact phrase; all words
near each other (within about twice the number of words); all words
anywhere; the same two with a misspelt word; and, only when fewer than
five verses have all the words, verses with all but one. Within a tier a
verse scores the sum of its words' rarity (rarer words count more, exact
words more than longer words they begin or typos), a little more for a
shorter verse, 35% more when it opens with the phrase, and 50% more if it
is one of 79 very well known verses (`popularVerses`, e.g. Psalm 23:4
before the other verses of Job that say "shadow of death"). Ties go to
canonical order.

### Archaic and modern forms

Both the verses and the query go through `stemWord`, so one word is one
key: a small table of old words and the modern words they stand for
(`archaicForms`, about 100 pairs: thee, thou, ye, thy, thine, hath, doth,
saith, spake, unto, upon, shalt, wilt (and will, folded into shall),
art, wast, wherefore, whosoever, alway, yea, mine, which and whom (folded
into who), brethren, and irregular verbs such as gave, took, came, saw,
knew, made), then plain endings (-s, -es, -ed, -ing, -eth, -est) taken
off and a final e dropped. So believeth, believes, believed and believe
are one word, and so are loveth/loves/loved, cometh/comes/came,
maketh/makes/made. A short list of words that only end like verbs
(honest, harvest, priest, this, Jesus) keeps its ending.

What this does not do: it knows no synonyms (hearken is not listen,
"anxious" is not "careful", "disciples" does not find "teach"); it cannot
tell a noun from a verb (will the noun and will the verb are one word); it
joins words that happen to fold together (hates and hat); it does not
know that "on" and "upon" are different from "in"; it does not fold
British and American spellings except by the typo rule (labour and labor
are one letter apart, so labor finds labour only when nothing else
matches); and modern translations' wording is not searched, only the
KJV's. "Which" and "who" are one word, so a search for "who" also finds
"which".

### The Ready tray

`ReadyTray` (`ChangeNotifier`, one per app controller, kept with it in an
`Expando` so no controller file changes) holds up to 12 prepared
passages, newest first. The API for anything that finds passages:

```dart
ReadyTray.of(controller).addReady(reading, source: 'search', heardAs: null)
```

`reading` is a `BibleReading`; `source` is `search`, or `listening` for a
suggestion from the verse listener, which also passes `heardAs`, the words
it heard; the row shows "Suggested while listening · heard as “…”".
Adding a passage already there moves it to the front. The tray is kept
while the app is open, so leaving and returning to the Slides page keeps
it, and it is **not** saved: a restart starts empty (a passage prepared
for last Sunday is not wanted this Sunday, and the search is two keys
away).

A row has **Send**, **+ next verse** (the next chapter's first verse at a
chapter's end), **Whole chapter**, **Save to Library** (as Bible verses,
once) and remove. Send goes through `LyricsController`, which gained one
small method, `showTransient`: the passage is a `LyricItem` that is not in
the library (so a Send never fills it), kept by the controller while it is
on the screens, and from there everything is the library's own path
(`show`, `next`, `clear`, `field` for each screen, Dim, background, Send
to, the slide cards, Black). Long passages split into slides by the
existing verse-to-slide rules. Extending a passage that is on the screens
keeps its slide and gives the screens the new words.

### Keys and Commands

On the Slides page, **/** or **Ctrl+F** puts the keyboard in the box (on
a phone with a keyboard, opens the sheet); Ctrl+F also from inside it.
In the box: **Up** and **Down** move the highlight, **Enter** puts the
highlighted result in Ready (or selects a Library item), **Ctrl+Enter**
sends it, **Esc** clears the box; a second Esc (box empty) hands the keyboard back to
the slides, so the arrow keys work without a click (and it never clears the
slide on the screens: that is the third Esc). Tapping a result prepares
it, a second tap within 0.45 s or the play button sends it. **Search the
Bible** is in Commands under Go to. Neither key clashes with an existing
one (`/` was unused; `?` is Shift+/).

### Phone

The Slides page starts with a search field. It opens a full-height sheet
(its own box, results below, the keyboard above them); tapping a verse
puts it in Ready and closes the sheet, the play button sends it and
closes it. Ready sits under the field, only when it has something in it.

### Known weak spots

- Modern wording that is not the same word ("plans to prosper you",
  "do not be anxious", "God-breathed") finds nothing: the KJV does not
  say it.
- A short typo-ed word (four letters) can match a different short word
  ("kwpt" finds "kept").
- With a book name as the first word, a query that was meant as words
  but has a word that is a book ("acts of faith") searches only that
  book; if the book has no match the words are searched everywhere.
- Very common phrases return many equally good verses; the 79 well-known
  verses are lifted, the rest follow canonical order.

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
