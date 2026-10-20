# Portable template schema v4

JSON contains these top-level fields: `schemaVersion` (integer 4 on export), `name`, `type`, `segments`, `display`. Versions 1–4 are accepted. Unknown fields are rejected, including controller data and approval records.

`type` is `service` or `rehearsal`, required for versions 3–4. It controls optional list grouping only; timing speed is chosen when loading a service. Versions 1–2 without a type default to Service, except the legacy starter named exactly `Quick rehearsal`, which becomes Rehearsal. Set the group explicitly in the editor for other old templates. Version 3 JSON requires Cuekeeper 0.6 or newer; older apps report an unsupported version. CSV still carries segments only and imports as Service.

`segments` contains 1–200 objects with `name` and integer `minutes` (1–99). Names are trimmed, 1–80 Unicode code points. Template names are unique without regard to case. Optional `speaker` (up to 80 single-line characters) and `notes` (up to 1,000 characters, multiline) are operator-only metadata; neither is sent to the display. JSON and full backups preserve them; CSV does not. Version 4 exports without duration protection require Church Service Timer 0.10 or newer. In 0.18, optional `protected: true` keeps a segment out of automatic time-recovery reductions; it is omitted when false. Files containing this optional field require 0.18 or newer. CSV does not preserve protection.

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

Each warning rule contains `seconds` (integer 0–5,999, unique within the shared rule set), `enabled` (boolean), `destination` (`operator` or `stage`), and `cue` (a complete text layout). Rules use time remaining per segment. Both destinations allow phone notifications. See `FEATURES-0.3.md`. `examples/quick-rehearsal.json` remains a version 1 compatibility example; `examples/styled-rehearsal.json` demonstrates version 2. Tinos faces are bundled with the Android app; font bytes are not exported. Import adopts the receiving device’s shared warning rules.

Static/flashing text must fit within 32 pixels. Scrolling is required when it does not fit. No image or video fields are accepted. Physical-layout approvals and local settings are never exported or accepted as part of this schema.

CSV headers are exactly `Segment Name,Duration (Minutes)`. UTF-8 with optional BOM, CRLF/LF, quoted commas and doubled quotes are supported. Entirely blank rows are ignored. Durations such as `05:30`, fractions, zero and negatives are invalid. A single invalid row blocks the full import and reports its row number. Exported CSV preserves segment names, ordering and durations only.

Imports are at most 1,048,576 bytes. The native document reader checks metadata where available and enforces this limit while reading before JSON/CSV parsing. Invalid UTF-8 is rejected. No incoming data is committed before Accept Import.
