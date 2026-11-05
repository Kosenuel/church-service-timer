# Cuekeeper 0.4 — service records and display ownership

## Live cues

Automatic warning panels and Stage cues now have the same 16-pixel gap as adjacent panels.

Open an existing Stage cue and choose **Delete cue**. Confirmation removes it from the shared list for every service. A cue already on the display remains visible until dismissed or replaced. New unsaved cues have no delete action. Deletion is saved atomically; a failed save retains the item and output, and a stale deletion cannot remove a different item that moved into its position.

## Reports

The default view is a compact list showing the service name, Live/Rehearsal type, local date and recorded duration. Tap any record to open its detail page: planned and actual duration, variance, pauses, net time adjustments, start/end dates, a segment chart and ordered segment cards. Per-record CSV/JSON export and confirmed deletion are available there; a delete icon also remains on the list.

**Export all records** offers CSV or JSON and always includes the entire saved history, even when a filter is active. CSV contains one row per segment, with repeated service metadata, exact seconds, UTC dates, timing uncertainty and missing-duration status. JSON preserves every record and segment in a `cuekeeper-service-reports` version-1 envelope. An export takes a snapshot when its dialog opens. Exported documents are not deleted when local reports are cleared.

**Graph** shows total recorded time, average variance, Ahead/On time/Behind counts, and paired planned/actual bars for every filtered record, oldest first. Tap a chart entry for details. Every bar uses the same zero-based scale. Unknown actual durations are labelled, not treated as measured zero. Partial or uncertain records are highlighted and excluded from comparative averages and outcomes. Recorded-time totals include all available durations, including those highlighted records.

Use **All services**, **Live only**, or **Rehearsals** to filter both views. Rehearsal durations are simulated service time; dates are real clock time. The combined view explicitly labels mixed durations. No records are silently truncated. The graph is based on existing local records; no new analytics service or network access is involved.

## End screen: each template owns its style

In **Templates → Edit**, use **Edit template end screen**. Changes are committed with **Save timeline**. Cancelling the editor leaves the template unchanged. **Use current default** copies the current Display default into this template.

In **Display**, choose **Defaults for new templates → Edit end screen** to change the initial style for future templates. Existing templates remain independent. The template selector in Display can also edit a particular template's end screen. A loaded service retains the end screen captured when it was loaded.

The initial style is:

```json
{
  "zero": null,
  "end": {
    "text": "Hallelujah",
    "bold": true,
    "italic": true,
    "effect": "scroll",
    "align": "center",
    "speed": 12,
    "height": 2,
    "font": "cuekeeper_matrix"
  }
}
```

`height: 2` is Tall, 14 pixels. The original Cuekeeper Matrix glyphs and renderer are unchanged.

## At Zero: shared by every service

**Display → At zero · all services** is independent of the template selector. **Use 00:00** restores the numeric zero; **Custom text** sets a shared styled message. Saving applies immediately to every template and the loaded service, including restored prior-session snapshots. Existing manual cues, automatic warnings, held output and disconnected output keep their existing priority rules.

Local state upgrades to version 4. Previous default At Zero becomes authoritative; old per-template zero values no longer override it. Portable JSON remains schema 2: the `zero` field is retained for compatibility, but import uses the receiving device's shared value. End-screen settings are preserved on import.

Only untouched old end screens (the exact original `Hallelujah` style) in defaults/saved templates receive the new bold, italic, tall default. Customized styles and loaded end-screen snapshots are preserved. Reports, saved cues, font imports and LED-shape preferences survive migration.

## Checks

`test/revision_04_test.dart` covers migration, ownership, exports, calculations, save failures, deletion, report navigation/filtering and UI previews. Its nine pure cases also run with `dart scripts/revision_04_smoke.dart`. The normal build script runs these alongside the previous timer, warning, renderer and UI tests.

Phone check after upgrading: delete/cancel a saved cue, change one template's end screen, change global At Zero while a service is running at zero, open/filter graph and detail views, and export all records through Android's document picker. No physical controller connection is added by this release.
