# Ready for 1.0.0: checklist

A draft for the owner to edit. It defines what "ready for general use" means before the version moves to 1.0.0. From 1.0.0 on, an incompatible change always means a new MAJOR version (see [Versioning](BUILD.md#versioning)), so the point is to be sure now which things the app promises to keep working.

Tick a box only when it has been checked on the real thing. Items marked **Repo** are already shown by what is in this repository (tests, documents or workflows); that does not replace a check on a real device where one is listed. Items marked **Open** have no proof in the repository yet. Use [test releases](BUILD.md#test-releases-pre-releases) (`1.0.0-rc.1`) to try the build on your own devices first.

## 1. Real-device testing

**Windows PC**

- [ ] Every step of "What to try on a real PC" in [WINDOWS.md](WINDOWS.md#what-to-try-on-a-real-pc) passed on real Windows hardware. **Open:** WINDOWS.md says the app has not been run on a real PC by anyone.
  - [ ] Second screen (step 11), including a screen with a different scale setting, unplugging it and the "open when a service starts" setting.
  - [ ] Full screen (step 15) and the mini timer (step 13), on one monitor and on two.
  - [ ] Notification-area countdown icon (step 14).
  - [ ] Sleep, hibernate and restart during a service (steps 2 and 3).
  - [ ] Download and install proven from an older version (step 16), using a real (not pre-release) newer version on the guide site.
  - [ ] Installer: fresh install, install over an older version, uninstall, and the app's "Open with" entry.
- [ ] A 1366 × 768 laptop and a 1920 × 1080 screen both look right (**Repo:** the window sizes are checked in tests; a real screen is not).

**Android phone and tablet**

- [ ] A phone test pass: start, pause and finish a service; full screen gestures and the notification tray; turning the phone round during a service; locked-screen operation. **Open.**
- [ ] A tablet test pass: the wide layout, orientation, and pairing as host and as second operator. **Open.**
- [ ] Pairing between two Android devices and between a phone and a PC, using the six-digit code. **Open** (the pairing protocol is covered by tests, [W2 evidence](w2-protocol-evidence.json) for the sign).
- [ ] LED sign, if you use one: connect, show a segment, a cue and the end screen on the real sign. **Repo:** the sign codec matches the Java codec used with real signs; **Open** for a sign on the current version.
- [ ] The Android app installs over the previous release, using the same release key and the next build number. **Repo:** the release workflow refuses to publish without the release key.

## 2. Data and compatibility

- [ ] You are willing to keep these stable from 1.0.0 (a change that an older version cannot open needs a MAJOR version): program files (JSON and CSV), backups, the saved state on a device, and the pairing and web-screen protocol. **Decision for the owner.**
- [ ] The format versions are written down. **Repo, partly:** [TEMPLATE-FORMAT.md](TEMPLATE-FORMAT.md) lists the program file versions and which app version reads each; backups carry a `schemaVersion` (`lib/domain/app_settings.dart`). **Open:** the pairing and web screen versions, and the saved-state version, in one list.
- [ ] An upgrade test from an earlier 0.x with real saved data: install the oldest build still in use, save programs, reports, cues and a backup, update to the candidate, and check everything opens. **Open.** **Repo:** WINDOWS.md says a backup made on either platform restores on the other, and the import code keeps older `schemaVersion`s readable; nothing here replaces a test with real data.
- [ ] Nothing in the app is refused by an older device without saying why. **Repo:** program and backup files that need a newer version say "needs this version or later" and the CHANGELOG names such changes. **Open:** pairing with a phone on an older version shows a clear message rather than failing silently.
- [ ] The rule is applied: reading the CHANGELOG since 0.35.0 shows no entry that needed a MAJOR version.

## 3. Distribution

- [ ] Windows installer: either signed with a code-signing certificate, or a deliberate decision not to sign, with the SmartScreen warning ("Windows protected your PC", then **More info** and **Run anyway**) explained where people download. **Repo:** the release notes and WINDOWS.md already explain the warning; **Open:** the decision.
- [ ] Google Play: published, or deliberately left out. **Repo:** [PLAY-RELEASE.md](PLAY-RELEASE.md) is a step-by-step checklist and the release workflow builds the signed bundle; **Open:** status of the Play listing.
- [ ] The guide site is current: download button, install steps for Android and Windows, and the privacy policy page. **Repo:** the release workflow copies each release to the guide site; **Open:** the site's own text.
- [ ] The privacy policy matches what the app does today (Check for updates, the optional automatic check, diagnostics by email). **Repo:** README and Settings › About › Your data describe it; **Open:** the policy page.
- [ ] The release notes for 1.0.0 are written for people, not only for the changelog. **Repo:** the workflow publishes each version's CHANGELOG section.
- [ ] A test release (`1.0.0-rc.1`) has been published, installed from the guide on a phone and a PC, and the real `1.0.0` came as an update from it. **Open.**

## 4. Quality

- [ ] The full test suite passes on GitHub Actions on `main`, and the release workflow's analysis and tests pass on the tag. **Repo:** both run on every release; tick it for the actual 1.0.0 commit.
- [ ] No known crash is open: the issue list has no open crash or data-loss report. **Open.**
- [ ] Accessibility pass on a phone and a PC: large text (system font size at its largest), **High contrast**, **Reduced motion**, and TalkBack or Narrator reading the main controls. **Repo:** High contrast and Reduced motion are settings (Settings › Appearance); **Open:** nobody has recorded a pass with them.
- [ ] A long-service check: a full service of 90 minutes or more runs without the display drifting or the app slowing. **Repo:** [PERFORMANCE-REVIEW.md](PERFORMANCE-REVIEW.md) and the soak script describe the method; **Open:** a recent result.

## 5. Support

- [ ] People can say how to report a problem. **Repo:** Settings › Feedback Center prepares an email; **Open:** the guide says where to send it and what to include.
- [ ] Diagnostics (Settings › Diagnostics) are understood by whoever answers: what they include, and that they contain no church content. **Repo:** the README says so.
- [ ] Someone is named to answer reports, and how quickly. **Open.**

## Open questions for the owner

These are yours to decide; nothing here has been decided in the draft.

1. **Which things are promised stable?** Program files, backups and the saved state, the pairing and web-screen protocol, the LED sign protocol: all, or only some? Anything left out can still change in a MINOR release, so say so in the guide.
2. **How far back must an upgrade work?** From every 0.x release, or from 0.30 and later, say?
3. **Windows signing.** Pay for a code-signing certificate before 1.0.0, or keep the unsigned installer and explain SmartScreen? If signed, who holds the certificate?
4. **Google Play.** Is it a condition of 1.0.0 that the app is published there, or does 1.0.0 mean the GitHub and guide downloads only?
5. **Real hardware.** Which Windows PCs, Android phones, tablets and LED signs must have passed, and who tests them?
6. **Support promise.** What do you commit to after 1.0.0: reply times, how long a version is fixed, whether an old version gets a fix (a PATCH release) once a newer one exists?
7. **Accessibility target.** Is a pass with TalkBack and Narrator required, or only large text, high contrast and Reduced motion?
8. **Release candidate.** How many days must `1.0.0-rc.1` run on your own devices, and through how many real services, before 1.0.0?
9. **Pairing with older versions.** After 1.0.0, must a 1.x phone and a 1.y PC always pair? The CHANGELOG has already had "needs this version or later" changes to pairing; is that still acceptable within a MAJOR version?
