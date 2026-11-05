# Church Service Timer 0.7 — Church profile, themes and Settings

The app is now called **Church Service Timer** in the launcher, header, opening screen, notifications, licenses and exported filenames. The Android package remains `org.kosenuel.cuekeeper` so an APK signed with the existing key upgrades the installed app and retains its data. Internal font IDs and warning intent identifiers also remain stable. Historical release documents retain their original release evidence.

## Settings

The bottom navigation now reads Live, Templates, Settings and Reports. Settings contains:

- **Church profile:** optional name, up to 80 Unicode characters on one line. Shown in the header, the Flutter opening screen after preferences load, and About. Android's initial native splash displays the new church-and-clock icon; it does not display a custom church name before local storage loads.
- **Appearance:** Midnight Lime, Royal Navy, Warm Ivory, Deep Plum and Slate Teal. Tapping previews a theme throughout the app; Save keeps it and Cancel/back restores the previous saved theme. Warning states stay amber and overdue states stay red, with darker equivalents in the light theme. The red End service button remains prominent. LED simulator colors and pixel data are unaffected.
- **Display settings:** all former Display-tab controls, including shared At Zero, template/default end screens, warning defaults, fonts and LED shapes.
- **Keep screen awake:** enabled by default, matching earlier behavior. Turning it off restores Android's normal automatic sleep while the app is visible. It does not override the power button or change warning alarms. A native application failure is shown separately from a successful preference save.
- **Backup & restore:** complete saved setup as a user-selected JSON file, with validated input and an explicit replacement confirmation.
- **About:** creator Kosenuel, installed Android version/build number, app description, local-data explanation, simulator limitations and font/software licenses.

## Identity and reports

Each newly loaded service snapshots the church name. Editing the profile afterwards affects the header and future services, but the loaded service and older reports retain their identity. Existing reports without a church name remain blank rather than being attributed retrospectively. Individual and bulk report JSON use new `church-service-timer-report(s)` type labels and schema version 2; CSV appends a Church column while retaining earlier column positions. Church values receive the same escaping and formula protection as other text columns.

The display labels **Service Matrix** and **Service Sq-Matrix** replace the old branded font names. Their stable IDs, glyph tables, rendering, sizes and styling are unchanged. Times New Roman remains an imported native font.

## Portable backups

Schema 1 backup envelope: `type: church-service-timer-backup`, `schemaVersion`, `createdUtc`, `data`. Data includes templates, display defaults, shared stage cues, reports, pixel shape, template grouping, church name, theme and screen-awake preference. It excludes the currently loaded/running service, transient simulator frames, alarms, Android permissions and imported font bytes. Restore returns to idle with a blank simulator; no old service resumes or cue is replayed.

Files are limited to 16 MiB and validated before saving. Missing preferences, unsupported schemas/themes, duplicate templates/reports, invalid timings and malformed JSON are rejected. Templates and cues keep their existing domain validation. A backup requiring Times New Roman needs that font imported on the receiving device first. Template imports retain their separate 1 MiB limit.

Restore replaces local collections and preferences; it does not merge. The review dialog shows file name, church, theme and record counts, and explains the replacement. A loaded Ready or running/paused service blocks restore. Atomic save failure leaves both the current setup and simulated frame unchanged. A successful retry clears the prior frame too. Export a current backup before restoring if the existing setup must be retained.

Saved-state schema 7 reads versions 1–6. Older installations default to a blank church profile, Midnight Lime and screen awake enabled. No signing key, package identity or hardware settings are changed.

## Validation

Coverage includes migration, all saved preferences, report identity, CSV protection, backup round trips and invalid input, missing fonts, save-failure retries, awake-flag failures, theme preview/cancel/restart, grouped settings navigation, About metadata, restored-frame clearing, five theme screenshots and narrow/enlarged-text layouts.

Device checks must include upgrade without data clearing; launcher/splash icon; church branding; light/dark readability; screen sleep on/off; report exports; and backup export/cancel/restore/restart. Physical sign delivery is still unimplemented.

Pre-build checks: all 91 standalone domain/import/backup checks pass; native Kotlin compiles against Android 36 and the installed Flutter embedding; Android resource compilation/linking accepts the launcher, adaptive/monochrome icons and launch themes. Both Matrix font assets match the previous release byte-for-byte after excluding their visible name fields. Key text/state colors in all five palettes exceed 4.5:1 against their surface colors (lowest 5.40:1, Warm Ivory).

Verified on 16 October 2026: Flutter analysis reported no issues and all 161 Flutter tests passed. All 18 updated/new screenshots were visually reviewed, covering Settings, About, Appearance, each of the five themes, Live phone/tablet, overtime, templates, reports and Matrix fonts. The existing grouping test emitted a nonfatal text-target tap warning; its grouping, editing and persistence assertions passed. The APK was independently verified as Church Service Timer, `org.kosenuel.cuekeeper`, version `0.7.0` (code 7), minimum API 24, target API 36. Its v2 signer certificate matches 0.6. The build reports a future Kotlin Gradle migration advisory but completes successfully with the pinned toolchain. Installation and Android device behavior remain to be checked; simulated test success does not establish physical LED delivery.
