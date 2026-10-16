# Church Service Timer 0.9 — Feedback Center

Settings now includes **Feedback Center** under Data & app. It collects a required title (up to 120 characters), message (up to 4,000 characters) and contact email or phone (up to 120 characters). Unicode and multiline messages are supported. Only these fields, the app name and installed version are included.

**Open email app** prepares a draft addressed to **kosenuel@gmail.com**. The operator reviews the draft and taps Send in the email app. Returning to Church Service Timer does not imply that the email was sent or delivered. The success notice explicitly explains this.

If no email app can open, or opening fails, the form retains its text and explains how to retry. **Copy feedback** copies the destination, subject and full message for pasting elsewhere. **Clear draft** requires confirmation and only clears this screen; an external email draft is unaffected. Drafts remain in memory while the page stays open, including normal email hand-off and return. They are not stored across closing the page or terminating the app.

The page follows the chosen theme and scrolls for narrow screens, larger text and the keyboard. Feedback does not require a new app account or backend. Sending requires an email app with a configured account and eventually network access; Church Service Timer itself does not transmit feedback directly.

## Implementation

`FeedbackMessage` normalizes and validates the fields before either operation. Single-line title/contact values cannot contain control characters. `DevicePort.composeFeedback` gives the UI a testable boundary; Android uses `ACTION_SENDTO` with a `mailto:` URI and fixed recipient. Subject and body are encoded independently, so characters such as `&`, `+`, `#`, line breaks and non-ASCII text cannot change recipients or add query fields. The native handler catches a missing mail activity and returns availability, not a delivery result. No SMTP password, API key or Gmail credential is in the APK. Saved-state schema 8 and backup schema 2 remain unchanged.

This follows Android's [email intent guidance](https://developer.android.com/guide/components/intents-common#Email) and [package visibility guidance for launching activities](https://developer.android.com/training/package-visibility/use-cases#start-activity).

## Validation

Standalone checks cover required fields, normalization, size limits, Unicode, multiline text, copy content and fixed-recipient URI encoding. Widget checks cover invalid forms, successful hand-off, missing mail apps, exceptions, retained text, copy/clear confirmation, the Android channel contract and narrow layouts with enlarged text. A new screenshot captures the filled Feedback Center; Settings and About baselines also change.

Pre-build checks on 17 October 2026 passed: static analysis with no diagnostics, all 103 standalone Dart checks, six native email encoding/validation checks, and native Kotlin compilation against Android 36. The existing version-code deprecation warning is nonfatal.

Flutter analysis and all **186 Flutter tests passed** on 17 October 2026. The new Feedback Center screenshot and updated Settings and About screenshots were reviewed; the other 20 baselines are unchanged. The existing grouping-test text-target warning remains nonfatal. The Android APK is verified as **0.9.0 (code 9)**, package `org.kosenuel.cuekeeper`, with the Church Service Timer label. Its v2 signing certificate matches 0.8.0, preserving the upgrade identity. SHA-256: `27a30b72d5a477084c7c6b6e83100fe13c37fcb88e313419cce7e86cc37a7347`.

The build helper deduplicates PATH after toolchain activation and restores its original value on exit. Five checks cover repeated activation, path equivalence, search order, empty entries and drive-root handling. A PowerShell 5 failure simulation verified failure reporting and restoration of the caller's PATH and working directory. The successful APK-only build reduced the actual console PATH from **8,361 to 1,501 characters**, resolving the earlier Windows command-length failure. The full test evidence is preserved separately because this build skipped tests already passed against unchanged app source. The helper records building, failed and built results explicitly.

Android email-client behavior still requires a phone check: open a draft, verify the destination/content and return without sending. No actual feedback email is sent by automated checks. The pinned Flutter toolchain's Kotlin migration advisory remains nonfatal; production signing and physical sign integration remain separate work.
