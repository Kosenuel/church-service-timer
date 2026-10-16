# Cuekeeper 0.6 — Compact templates and consistent Live alignment

## Live alignment

The timer gauge occupies the full available card width in every state. Previously its column shrank to the arc width when no warning message was present; the parent placed that narrower column at the left. A warning row expanded the column, making the arc move. Ready, normal, paused, warning, overtime and ended states now share a horizontal center without changing timer logic or the original Matrix font.

The Display preview header fills the card. Its title stays at the left, with Simulator, Display connected or Disconnected at the right. Both labels can wrap with enlarged text. The prototype's adapter remains a simulator; it does not claim a physical connection.

## Templates

The list shows a service name, segment count, duration and chevron per compact row. Tapping opens a detail page with ordered segments, an end-screen summary and enabled-warning count. Edit, Duplicate, Export JSON/CSV and confirmed Delete live on that page. New is the primary list action; Import sits below the rows. Long names and larger text increase row height rather than clipping.

Duplicate preserves all settings and generates a unique name ending in `(copy)` or `(copy 2)`, within the 80-character limit. Editing and deletion validate the reviewed template rather than trusting a stale list index. Changes use the existing atomic persistence mechanism and do not change loaded service snapshots or historical reports.

Single list is the default. List options can group Services and Rehearsals; this preference survives restart. Each template's group is explicit and editable. It organizes templates only, independent of the rehearsal speed chosen in Live. No sample templates from the design preview are added to saved data.

Saved-state version 6 adds the grouping preference and accepts versions 1–5. Template JSON version 3 adds `type`; versions 1–2 remain readable. Legacy templates default to Service except the starter named exactly Quick rehearsal. Original cue formatting, display settings, reports and LED preferences are retained. See `TEMPLATE-FORMAT.md` for interchange details.

## Verification

Regression coverage includes gauge-center geometry across phases on phone/tablet, right-edge badge placement for all statuses with enlarged text, compact row/detail screenshots, template grouping/import/restart, duplicate naming and settings, confirmed deletion, stale references and persistence failures. Full Flutter tests, screenshot review and APK validation are required before distributing this release. Physical sign validation remains separate.
