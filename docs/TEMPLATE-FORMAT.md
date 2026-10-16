# Portable template schema v2

JSON contains exactly these top-level fields: `schemaVersion` (integer 2 on export), `name`, `segments`, `display`. Versions 1 and 2 are accepted. Unknown fields are rejected, including controller data and approval records.

`segments` contains 1–200 objects with `name` and integer `minutes` (1–99). Names are trimmed, 1–80 Unicode code points. Template names are unique without regard to case.

`display` contains `zero` (null means 00:00, otherwise a text layout), `end` (a text layout), `cues` (4–6 text layouts), and `warnings` (0–6 warning rules). Missing warnings migrate to an empty list. The shared saved-cue library and service reports are local data and are not part of template exports.

Every text layout contains all fields:

| Field | Values |
|---|---|
| `text` | 1–160 characters; nonblank; supported pixel glyphs only |
| `bold`, `italic` | booleans |
| `effect` | `static`, `scroll`, `flash` |
| `align` | `left`, `center`, `right` |
| `speed` | integer 4–24 pixels/second |
| `height` | 1 (7 pixels) or 2 (14 pixels) |
| `font` | `cuekeeper_matrix`, `service_serif`, `clear_sans`; defaults to `cuekeeper_matrix` when absent in older data |

Each warning rule contains `seconds` (integer 0–5,999, unique within the template), `enabled` (boolean), `destination` (`operator` or `stage`), and `cue` (a complete text layout). Rules are evaluated per segment. See `FEATURES-0.2.md` for delivery and priority behavior. `examples/quick-rehearsal.json` remains a version 1 compatibility example; `examples/styled-rehearsal.json` demonstrates version 2.

Static/flashing text must fit within 32 pixels. Scrolling is required when it does not fit. No image or video fields are accepted. Physical-layout approvals and local settings are never exported or accepted as part of this schema.

CSV headers are exactly `Segment Name,Duration (Minutes)`. UTF-8 with optional BOM, CRLF/LF, quoted commas and doubled quotes are supported. Entirely blank rows are ignored. Durations such as `05:30`, fractions, zero and negatives are invalid. A single invalid row blocks the full import and reports its row number. Exported CSV preserves segment names, ordering and durations only.

Imports are at most 1,048,576 bytes. The native document reader checks metadata where available and enforces this limit while reading before JSON/CSV parsing. Invalid UTF-8 is rejected. No incoming data is committed before Accept Import.
