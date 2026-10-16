# Portable template schema v1

JSON contains exactly these top-level fields: `schemaVersion` (integer 1), `name`, `segments`, `display`. Unknown fields are rejected, including controller data and approval records.

`segments` contains 1–200 objects with `name` and integer `minutes` (1–99). Names are trimmed, 1–80 Unicode code points. Template names are unique without regard to case.

`display` contains `zero` (null means 00:00, otherwise a text layout), `end` (a text layout), and `cues` (4–6 text layouts).

Every text layout contains all fields:

| Field | Values |
|---|---|
| `text` | 1–160 characters; nonblank; supported pixel glyphs only |
| `bold`, `italic` | booleans |
| `effect` | `static`, `scroll`, `flash` |
| `align` | `left`, `center`, `right` |
| `speed` | integer 4–24 pixels/second |
| `height` | 1 (7 pixels) or 2 (14 pixels) |

Static/flashing text must fit within 32 pixels. Scrolling is required when it does not fit. No image or video fields are accepted. Physical-layout approvals and local settings are never exported or accepted as part of this schema.

CSV headers are exactly `Segment Name,Duration (Minutes)`. UTF-8 with optional BOM, CRLF/LF, quoted commas and doubled quotes are supported. Entirely blank rows are ignored. Durations such as `05:30`, fractions, zero and negatives are invalid. A single invalid row blocks the full import and reports its row number. Exported CSV preserves segment names, ordering and durations only.

Imports are at most 1,048,576 bytes. The native document reader checks metadata where available and enforces this limit while reading before JSON/CSV parsing. Invalid UTF-8 is rejected. No incoming data is committed before Accept Import.
