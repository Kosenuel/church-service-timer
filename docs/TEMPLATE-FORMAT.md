# Portable program schema v5

JSON contains these top-level fields: `schemaVersion` (4 for whole-minute programs, 5 when seconds are present), `name`, `type`, `segments`, `display`. Versions 1–5 are accepted. Unknown fields are rejected, including controller data and approval records.

`type` is `service` or `rehearsal`, required for versions 3–5. It controls optional list grouping only; timing speed is chosen when loading a service. Versions 1–2 without a type default to Service, except the legacy starter named exactly `Quick rehearsal`, which becomes Rehearsal. Set the group explicitly in the editor for other old templates. Version 3 JSON requires Cuekeeper 0.6 or newer; older apps report an unsupported version. CSV still carries segments only and imports as Service.

`segments` contains 1–200 objects with `name` and integer `minutes` and optional `seconds` (0–59; omitted when zero). New edits/imports/starts require a total duration of 1–3,599 seconds. Saved legacy programs up to 99:59 remain readable but must be shortened before saving or starting. Names are trimmed, 1–80 Unicode code points. Template names are unique without regard to case. Optional `speaker` (up to 80 single-line characters) and `notes` (up to 1,000 characters, multiline) are operator-only metadata; neither is sent to the display. JSON and full backups preserve them; CSV does not. Version 4 exports without duration protection require Church Service Timer 0.10 or newer. In 0.18, optional `protected: true` keeps a segment out of automatic time-recovery reductions; it is omitted when false. Files containing this optional field require 0.18 or newer. CSV does not preserve protection.

`display` contains `zero` (null means 00:00, otherwise a text layout), `end` (a text layout), `cues` (0–6 legacy template layouts), and `warnings` (0–6 rules). Missing warnings migrate to an empty list. In 0.3, accepted imported cues merge into the shared Live list, preserving unique text/style combinations. Template exports retain their legacy `cues` field, not the current shared list. The shared Live cues, LED shape preference, and reports are local data outside this interchange format.

In 0.4, `end` belongs to the template and is editable in its timeline editor. New templates copy the current default (initially bold, italic, tall `Hallelujah`, centered scrolling at 12 pixels/second in Cuekeeper Matrix). `zero` remains in exported JSON for compatibility, but import ignores its value and uses the receiving device’s shared At Zero setting. At Zero applies to saved templates and loaded services.

Every text layout contains all fields:

| Field | Values |
|---|---|
| `text` | 1–160 characters; nonblank; supported pixel glyphs only |
| `bold`, `italic` | booleans |
| `effect` | `static`, `scroll`, `flash` |
| `align` | `left`, `center`, `right` |
| `speed` | integer 4–24 pixels/second |
| `height` | 1 (7 pixels) or 2 (14 pixels) |
| `font` | `cuekeeper_matrix`, `cuekeeper_sq_matrix`, `tinos`; legacy `times_new_roman` selections migrate to `tinos`; absent/retired `service_serif`/`clear_sans` selections migrate to `cuekeeper_matrix` |

Each warning rule contains `seconds` (integer 0–5,999, unique within the shared rule set), `enabled` (boolean), `destination` (`operator` or `stage`), and `cue` (a complete text layout). Rules use time remaining per segment. Both destinations allow phone notifications. See `history/FEATURES-0.3.md`. `examples/quick-rehearsal.json` remains a version 1 compatibility example; `examples/styled-rehearsal.json` demonstrates version 2. Tinos faces are bundled with the Android app; font bytes are not exported. Import adopts the receiving device’s shared warning rules.

Static/flashing text must fit within 32 pixels. Scrolling is required when it does not fit. No image or video fields are accepted. Physical-layout approvals and local settings are never exported or accepted as part of this schema.

Single-program CSV headers are `Segment Name,Duration (Minutes)` with optional `Seconds`. The exporter includes Seconds when any segment uses them. UTF-8 with optional BOM, CRLF/LF, quoted commas and doubled quotes are supported. Entirely blank rows are ignored. Minutes and Seconds are separate whole integers. Colon notation, fractions, negative values and a combined zero duration are invalid. A sub-minute segment can use minutes=0 and seconds=35. A single invalid row blocks the full import and reports its row number. Exported CSV preserves segment names, ordering and durations only.

Single-program imports are at most 1,048,576 bytes; bundles are at most 16 MiB. The native document reader enforces the outer 16 MiB limit while reading; the parser applies the smaller single-program limit before accepting it. Invalid UTF-8 is rejected. No incoming data is committed before Accept Import.


## Other spreadsheets (0.26)

A CSV without the headers above (for example a church's own `Item,Time (mins),Who` sheet) opens **Match spreadsheet columns** instead of an error. The app shows the sheet, guesses each column from its title or, without titles, from its values, and lets the operator choose:

- **Segment name** and **Duration** (required);
- how durations are written: detected automatically, minutes (`5`, `5.5`), minutes:seconds (`05:30`, also `1:05:30`) or seconds (`330`); detection also reads `5 min`, `5m 30s`, `90s` and `1 hour`;
- **Speaker** and **Private operator notes** (optional);
- a **Program name** column (optional), which splits the rows into one program per name; otherwise all rows form one program named after the file;
- whether the first row holds column titles.

Rows with neither a name nor a duration are left out. Any other row without a name, with an unreadable duration or longer than 59:59 is listed by its spreadsheet row number, and nothing is imported until it is fixed. A valid result goes to the usual import review. The choice is remembered on the phone for up to 20 layouts, keyed by the header row, so next week's sheet in the same layout only needs Continue. Excel and Google Sheets files must be saved as CSV first.

## Bulk program bundles (0.19)

JSON has `type: "church-service-timer-programs"`, `schemaVersion: 1`, and a `programs` array of 1–200 complete program objects. Formatting and second precision are preserved; private notes are omitted unless the export checkbox is selected. At Zero and warning rules adopt the receiving phone's shared settings.

CSV uses `Program,Type,Segment number,Segment Name,Duration (Seconds),Speaker,Protected` and an optional `Private notes` column. Program name groups rows; segment numbers must run consecutively from 1. Duration is total integer seconds. CSV carries the rundown and metadata, not end-screen formatting. JSON is the lossless format when notes are included.

The import preview lists every incoming program. Existing programs are not replaced; colliding names receive numbered suffixes. All candidates are validated before one atomic save; a malformed entry cancels the entire import. Bundles exclude live service state, reports, credentials and pairing approvals.
