# Screens panel: design note

What a stage screen shows used to be set in five places (the second
screen's settings, each paired stage screen's dialog, Web screens, Full
screen, the stage simulator) and the Slides page had its own **Send to**
boxes. The Screens panel replaces all of them with one idea: every screen
is in one named **group**, and each group shows one thing. A **scene**
sets every group at once, and a program segment can name a scene that is
applied when the segment starts. The approved mockup
(`screens-panel-mockup.html`) is the reference for layout, wording and
behaviour; the app's own theme and components replace its styling.

This note is the plan the feature is built to and is kept current.

## What a group can show (`lib/domain/screen_groups.dart`)

`screenShows`, one choice per group:

| Saved value | Words | What the group's screens draw |
|---|---|---|
| `timer` | Timer only | the countdown |
| `current` | Timer and segment name | the countdown with the segment band |
| `next` | Timer and up next | the countdown with the up next band |
| `only` | Up next only | the next item (end screen or clock when nothing is next) |
| `slides` | Slides | the slide on the screens; the countdown when none |
| `monitor` | Slides and timer | the confidence monitor; the countdown when no slide |

The first four are `stageLayouts`, unchanged. A group also keeps a
`fallback`: the last of those four it showed (default `timer`). While a
group shows Slides or Slides and timer and no slide is up (nothing sent,
after **Clear slide**, or Black for the confidence monitor), it shows the
countdown in its fallback layout, so it is never blank.

## Data model

`AppState.screens` (`ScreenSetup`, saved key `screens`):

- `groups`: `[{id, name, show, fallback}]`, 1 to 12 groups, names 1 to
  40 characters, unique without regard to case. Ids are short random
  strings kept for life (`g` + 8 letters), except the groups made by the
  migration (`room`, `web`, `stage`, `stage-2`, ...).
- `defaultGroup`: the group a screen joins when it connects for the first
  time, and where screens of a deleted group go.
- `scenes`: `[{id, name, shows: {groupId: show}}]`, at most 24, names
  unique. A scene only lists the groups that existed when it was saved
  (or updated); applying it leaves other groups alone, and ignores ids
  of groups deleted since.
- `members`: screen key to group id, **on this device only** (removed in
  `exportBackup`, kept on restore). Keys:
  - `this`: this device's own stage picture: the second screen window on
    a PC, host **Full screen**, and the **stage simulator**. They are one
    screen in the panel ("This computer" / "This phone"), because they
    show the same picture of the same device.
  - `pair:<saved device id>`: a paired phone or tablet (role stage or
    viewer), by its saved pairing identity.

  A key with no entry, or naming a group that no longer exists, is in the
  default group. A screen is therefore always in exactly one group.

Web browsers are not stored on the host (they get a new token each time
they join). A browser remembers its group itself (`localStorage`) and
sends it when it joins; a per-group link (`http://host:8080/?group=<id>`)
does the same for a browser opened from it. A browser naming no group,
or one that no longer exists, joins the default group. Moving a web
screen in the panel changes its group at once, and the page saves the
new one, so it stays there when it joins again.

A missing `screens` key (data from before this feature) is migrated once
at start (below), after the second screen's settings and the pairing
memory have been read, and saved. Until that save succeeds (a corrupt or
unwritable state) the same migration is used from memory.

The old per-screen settings (`SecondScreen.layout`, `fullScreenLayout`,
`simulatorLayout`, `webStage.stageLayout`, `SavedPairDevice.layout` and
the `LyricsLook` Send to booleans) are still read and written unchanged,
so an older version opened after this one still finds them, but nothing
in this version reads them after the migration.

## Migration (old settings to groups)

Inputs: this device's layout (the second screen's on a PC, Full screen's
on a phone or tablet) and Send to *Second screen*; the web screens'
layout and Send to *Web screens*; each saved paired screen's layout and
Send to *Stage screens*. A screen's choice is `slides` if its Send to box
was ticked, else its layout; the fallback is its layout either way.

| Old settings | Groups made |
|---|---|
| this and web the same | **Room 1** {this, web} (default) |
| this and web differ | **Room 1** {this}, **Web screens** {web} (default) |
| no paired screens | **Stage** {} with the Stage screens choice |
| all paired screens the same | **Stage** {all paired} |
| paired screens differ | **Stage** {the most common choice; ties: the first saved}, then **Stage 2**, **Stage 3** ... for each other choice in the order first seen |

The default group is the one holding the web screens, because every
browser joins as a new screen after the update and must keep showing
what web screens showed. A new install runs the same migration with the
old defaults: Room 1 shows Slides (Send to Second and Web were on), Stage
shows Timer only (Send to Stage was off).

What is not carried over: the stage simulator's own layout. The
simulator now shows This computer's group (it was a preview of a stage
screen, not a screen people watch). On a PC, Full screen already
followed the second screen, so nothing changes there.

## Snapshots (what each screen receives)

The host decides per screen. `ScreensController.decorate(data, key,
kind)` adds to the snapshot a screen would get anyway:

- `stageLayout`: always one of the four countdown layouts: the group's
  choice, or its fallback for Slides and Slides and timer. Every older
  screen understands it.
- `stageShow`: the group's choice (new; older screens ignore it).
- `lyrics`: the slide, only for a group showing `slides` (as Send to did).
- `confidence`: only for a group showing `monitor` while a slide (not
  Black) is up: `{v, key, kind, label, text, title, detail, reference,
  next: {label, line}}`. Older screens ignore it and show the countdown in
  the fallback layout, which is the safe fallback for a screen that does
  not know the confidence monitor. No version check is needed for this;
  the pairing hello now also carries the app version and a `features`
  list (`confidence`), so the panel can say "Older app: shows the
  countdown" beside such a screen.

The web page gets the same three things through `/api/state` (`layout`,
`show`, `lyrics`, `confidence`) and its `group` (`{id, name}`).

Overrides keep today's order on every screen (`StageSurface`): sharing
stopped, then a quick message to that screen, then a slide (Slides) or
the confidence monitor (Slides and timer), then Blank, cues, Show clock
and the countdown. So, as before, a slide stays up over Blank and cues on
the screens showing slides, and Black (from the Slides page) blacks
those. The confidence monitor shows the countdown time on its right
whatever Blank or a cue does, because it is for the person on stage; a
quick message still covers it. The LED sign is not touched.

## The confidence monitor (`lib/pairing/confidence_monitor.dart`)

For a worship leader or speaker facing the room. On the stage theme's
background, never a picture:

- Left, about 62% of the width: the slide's words, as large as fits,
  in the theme's text colour (a label line above in the accent).
- Right: the countdown in fixed-width digits; amber in the warning
  period; in overtime red with `+mm:ss`. Gentle: red digits and a red
  frame round the time panel. Strong: the time panel turns red with dark
  digits. Strongest: as Strong, pulsing. Only the panel changes, so the
  words stay readable. Under it, NEXT and the next slide's label and
  first line ("Chorus · It is well with my soul"), or "Last slide".
- Upright (a phone on a stand): the words on top, the time and next
  below.
- With no slide showing: the countdown, full size, in the fallback layout.

## Scenes and segments

- **Save as scene** stores what every group shows now (not Shows cues). Scenes can be
  renamed, updated (to what the groups show now) and deleted. A scene is
  lit in the panel while every group it lists shows what it says.
- A program segment may name a scene: `Segment.sceneId` and
  `Segment.sceneName`, saved as `"scene": {"id": ..., "name": ...}` in
  programs, program files and backups (only when set, so plain programs
  stay readable by earlier versions; a program with a scene is not).
- When a segment **starts** (Start, Next, a jump, Undo back into it, a
  paired operator doing any of these), its scene is applied in the same
  save as the move. The operator can change any group afterwards; the
  next segment with a scene takes over when it starts. A segment with no
  scene changes nothing.
- A scene is found by id, then by name (ignoring case), so a program
  from another device uses a scene of the same name here. Neither found:
  the segment changes nothing, and the program editor says quietly
  "Scene “Worship” is not on this device. This segment changes nothing."

## Shows cues (per group)

`ScreenGroup.cues`. What counts as a cue: whatever puts something other
than the countdown, clock or end screen on stage screens from Live: a
stage cue (`cue` action), a warning cue (`automaticCue`, stage
warnings) and a message from Live's composer (`message` action), all of
which `Session.hasManualCue` / `hasAutomaticCue` cover, plus quick
messages to stage screens (`quickMessage`). Blank, Black and Show clock
are not cues and apply as before.

- The host marks a snapshot with a cue showing (`cue: true`) and adds
  `plain`, the display fields of the same snapshot without the cue
  (`stageCueKeys`). `decorate` always takes `plain` off; for a group with
  cues off it puts the `plain` fields in place of the cue's, drops `cue`,
  and drops `quickMessage`, `messageId` and `messageSeen` (restoring
  `blank`). An older paired or web screen draws what it is sent, so it
  never sees a cue either.
- Cues on, countdown layouts: as before.
- Cues on, Slides: a full-screen cue would hide the words the person is
  singing from, so it is drawn as a band across the bottom (a top banner
  cue across the top), with the existing banner colours and flash, still
  and wrapped (`stageSlideCueText`); the slide's words re-fit above the
  band. Decision: a full-screen cue never covers the whole slide. A
  quick message still covers the slide, as before (it is meant to stop
  the speaker).
- Cues on, Slides and timer: the cue takes the time's place in the right
  panel, the time stays in the panel's heading, the words stay.
- Defaults: the migration sets Stage (and Stage 2...) on, Room 1 and Web
  screens off. New groups start off, with the switch on the card. This
  changes what the second screen and web screens did (they showed every
  cue); the CHANGELOG says so.
- The stage simulator on Live always shows cues (`decorate(cues: true)`):
  it is the operator's own preview of a stage screen, and a cue sent must
  be seen there. Full screen and the second screen follow the group.
- Scenes save and restore what a group shows, not Shows cues: it says
  who looks at the screens, not what the moment needs.
- The LED sign is unchanged.

## The LED sign's preview

- The display in use is one of the LED sign, stage screens or the
  simulator (`AppController.destination`), and the sign is only sent
  output while it is the display. So the sign gets its own preview on
  Live when a real sign is the display: a small strip (its 32 × 16 dots,
  its name, its state) above the stage picture, which is what this
  device's own screen shows (its group). With the LED simulator as the
  display the big preview is the simulated sign, as before, and the
  Simulate chooser (LED sign or Stage screen) stays: it decides what the
  Simulator stands in for, not only what the preview shows. Without a
  sign nothing changes, so churches without one lose no space.
- The Screens panel has an LED sign card beside the groups, shown when a
  sign is set up or the LED simulator is in use: the dots, its state
  (Connected, Connected · output held, Reconnecting…, Not found) and
  "Shows the countdown and cues. Never slides." It has no tiles and no
  group.
- The dots are `HardwareDisplay.preview`: the app's copy of what it last
  sent and the sign accepted, never a read-back, and the wording says
  "what was sent to it". Not connected, the picture is dimmed and the
  state is in the warning colour.

## Backups

- Backups carry `screens` (groups, default and scenes; never `members`)
  when there is at least one scene, as schema version 13; plain backups
  stay at the version they were. Restoring one replaces groups and
  scenes; this device's members stay, and a screen whose group is gone
  is in the default group.
- Programs carry scene id and name only (above).

## What replaces what

| Before | Now |
|---|---|
| Settings › Screens & devices › Second screen: layout tiles | "Shows: Room 1 · Slides" and **Screens** |
| Paired device › Screen options: layout tiles | the group chooser, what that group shows, and **Screens**; the old "Screen group" (who gets quick messages) is now called **Message group** |
| Web screens: "Stage displays show" tiles | "Web screens join Room 1 ..." and **Screens**, with per-group links |
| Full screen's layout tiles (phone) | the group line and **Screens** |
| Simulator's layout tiles in Choose display | the group line and **Screens** |
| Slides page Send to boxes | the groups showing slides and **Screens**; with none, "No screens are showing slides." and **Show slides in Room 1**, both in the look section and beside what is on the screens |

## Screen awake

`wantsScreenAwake` keeps the lyrics rule with the new meaning of "a slide
is on a screen": a slide or Black is up and at least one group with a
screen in it shows Slides or Slides and timer.

## Decisions the owner may overrule

- The default group is the one holding the web screens (Room 1), so a
  new paired phone joins Room 1, not Stage.
- The stage simulator's own old layout is not migrated; it follows This
  computer's group (and always shows cues).
- The old quick-message audience groups (General, Preacher, Choir, Media
  desk) stay, renamed **Message group**, instead of becoming screen
  groups.
- Black from the Slides page puts Slides groups to black and turns the
  confidence monitor back to the countdown.
- Programs carry a scene's id and name only, not its definition; backups
  carry the definitions.
- A program with a scene on a segment cannot be opened by an earlier
  version (its segment has a new field).

## Phases

1. Domain model, migration, `ScreensController`, unit tests.
2. Per-group snapshots on every screen type, the confidence monitor in
   the app and on the web page.
3. The panel, the Live button and header icon, Commands.
4. Old choosers and Send to replaced.
5. Scenes on segments, the program editor, import and export.
6. Goldens, this note, CHANGELOG.
