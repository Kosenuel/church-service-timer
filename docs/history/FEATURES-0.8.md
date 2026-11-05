# Church Service Timer 0.8 — Compact lists and church banners

Reports and Settings now follow the compact Templates list style while retaining the selected interface theme.

## Reports

Records share a rounded surface with dividers. Each row shows the service name, local date/start time, recorded duration, timing outcome and a rehearsal badge when relevant. Rehearsal durations explicitly say simulated. Partial or uncertain records are labelled as such rather than assigned an ahead/behind result. Rows open the existing detailed report page.

Individual deletion is on the detail page, with confirmation. Export all, Clear all, All/Live/Rehearsal filters and List/Graph remain above the list. Bulk export still includes every record regardless of the current filter. Detailed segment timing and charts are preserved.

## Settings and display ownership

The Settings hub groups compact rows under Personalization, Service & display, and Data & app. Subpage rows have chevrons; Keep screen awake remains directly adjustable.

About credits **I-Proton** and shows the installed app version.

Display settings no longer has an Editing selector. At Zero remains global. End-screen and automatic-warning defaults are explicitly labelled **Defaults for new templates**; changing them does not rewrite existing templates or the loaded service. Fonts, stage cues and LED shape retain their global scope.

Each template's editor now includes its automatic-warning rules alongside its end screen. Warning threshold, destination, enabled state, text and formatting use the same editor as Live. Changes remain local drafts until **Save timeline**; leaving the editor discards them. Saved changes take effect the next time that template is loaded. Live warning editing retains its existing behavior for the loaded service and matching saved template.

## Church profile banner

Church profile has a wide, selectable **3:1 banner**, not a square avatar. The picker recommends **1200 × 400 pixels**. It accepts JPEG, PNG or WebP up to **5 MB (5,000,000 bytes)** and 40 megapixels. It uses Android's document picker, so no broad photo-library permission is requested.

Import checks the actual encoded image format and dimensions, corrects available EXIF orientation, scales uniformly and crops from the centre. It creates a 600 × 200 PNG (at most 500 kB), without retaining the original photo or its metadata. The original file is untouched. Place important details near the centre; tall photos lose more of their top and bottom. The visible preview shows the crop before **Save church profile** commits it together with the name. Cancel/back discards the draft; picker cancellation or rejection retains the previous preview.

Without a custom image, a built-in church landscape is drawn at the banner's native ratio in the selected theme. **Use built-in banner** previews the fallback; Save makes the reset persistent. The banner belongs to Church profile and does not replace the app launcher icon or report identity.

Saved-state schema 8 reads schemas 1–7; older installations use the built-in banner. Portable backup schema 2 includes the reduced banner and still imports schema 1 backups. Image decoding is validated before publishing a changed banner or a restored backup; a failed save leaves committed data intact.

## Validation and device checks

New checks cover banner migration and backup compatibility, invalid image metadata, pixel decoding, failed-save/retry behavior, temporary previews, default reset, template warning ownership and draft cancellation, compact report navigation, and narrow/enlarged-text layouts. Screenshots include both profile banner states, Display defaults and the template warning section, along with updated Reports and Settings views.

Verified on 17 October 2026: Flutter analysis reports no issues and all 176 Flutter tests pass. All eight new or changed screenshots were reviewed; the other 14 baselines remain unchanged. The custom banner renders correctly and template warning edits pass draft, save and restart checks. The APK is Church Service Timer 0.8.0 (code 8), package `org.kosenuel.cuekeeper`, minimum API 24 and target API 36; its v2 signature matches the previous release. All 98 standalone Dart checks and seven native crop geometry checks pass, and native Kotlin compiles against Android 36. The existing grouping test emits a nonfatal text-target warning; its assertions pass. Android installation and real image-picker behavior still require phone testing.

On a phone, import a landscape image, a portrait photo with EXIF rotation and a transparent PNG. Confirm the 3:1 preview is upright and unstretched, saving survives restart, picker cancellation and an image above 5 MB preserve the old banner, and built-in reset works. Restore a new backup on a second installation and an older schema 1 backup. Also check compact lists with enlarged Android text and confirm each template's warnings remain independent. These device checks are separate from source, geometry and widget tests. Physical sign delivery is still unimplemented.
