# Publishing on Google Play

A step-by-step checklist for getting Church Service Timer onto Google Play, and for every release after that. The store text and graphics are in [`play/`](../play); regenerate the graphics with `node scripts/play_assets.js`.

- **Package name:** `io.github.immanuelokose.churchservicetimer`
- **Account:** personal developer account (created October 2026)
- **Privacy policy:** https://immanuelokose.github.io/church-service-timer-guide/privacy-policy/

## 1. Create the app (once)

In Play Console, **Create app**:

| Field | Value |
| --- | --- |
| App name | Church Service Timer |
| Default language | English (United Kingdom) – en-GB |
| App or game | App |
| Free or paid | Free |

Accept the declarations.

## 2. Play App Signing with the existing release key (once, before the first upload)

We use the **existing release key** as the app signing key. People who installed the APK from GitHub can then update from Play, because both builds are signed with the same key. This has to be set before the first bundle is uploaded; it can't be changed later.

1. In **Test and release › Setup › App signing**, choose **Use a different key** (not "Use Google-generated key"), then **Export and upload a key from Java keystore**.
2. Download the **PEPK tool** and the **encryption public key** that the page offers.
3. On the computer that holds the release keystore, run:

   ```
   java -jar pepk.jar --keystore=release.jks --alias=<your key alias> \
     --output=play-signing-key.zip --include-cert --rsa-aes-encryption \
     --encryption-key-path=encryption_public_key.pem
   ```

   Enter the keystore and key passwords when asked, then upload `play-signing-key.zip` on that page.
4. **Upload key:** CI already signs bundles with the same release key (`CST_KEYSTORE_*` secrets), so register that key's certificate as the upload key:

   ```
   keytool -export -rfc -keystore release.jks -alias <your key alias> -file upload_certificate.pem
   ```

   Upload `upload_certificate.pem` when asked. (A separate upload key is safer, because it can be reset if it leaks; it can be added later under **App signing › Request upload key reset**.)
5. **Keep the keystore safe.** It's now both the GitHub APK key and the Play app signing key. Keep an offline backup, and never commit it.

## 3. First upload: internal testing

1. Tag a release as usual (`v0.30.1` or later). The release workflow attaches `Church-Service-Timer-<version>.aab`.
2. In **Test and release › Testing › Internal testing**, create a release, upload the `.aab`, and paste that version's CHANGELOG section as the release notes (shorten to 500 characters).
3. Add yourself (and anyone helping) as internal testers, then install from the opt-in link.

## 4. Store listing

**Grow users › Store presence › Main store listing:**

| Field | File |
| --- | --- |
| App name | `play/listing/en-GB/title.txt` |
| Short description (80) | `play/listing/en-GB/short-description.txt` |
| Full description (4000) | `play/listing/en-GB/full-description.txt` |
| App icon (512 × 512) | `play/graphics/icon-512.png` |
| Feature graphic (1024 × 500) | `play/graphics/feature-graphic.png` |
| Phone screenshots | `play/graphics/phone-*.png` (1080 × 1920) |
| 7-inch and 10-inch tablet screenshots | `play/graphics/tablet-*.png` (2560 × 1600) |

**Store settings:** category **Productivity**; contact email `immanuelproton@gmail.com`; website https://immanuelokose.github.io/church-service-timer-guide/.

## 5. App content (Policy › App content)

| Section | Answer |
| --- | --- |
| Privacy policy | https://immanuelokose.github.io/church-service-timer-guide/privacy-policy/ |
| Ads | No, the app doesn't contain ads |
| App access | All functionality is available without special access (no sign-in) |
| Content rating | Questionnaire category **Utility, productivity, communication or other**. No violence, sexuality, language, controlled substances or gambling; users don't interact or share content with strangers; no location sharing; no purchases. Expect **Everyone / PEGI 3** |
| Target audience | **18 and over** (a tool for church staff and volunteers); not designed for children |
| News app | No |
| Health, financial features, government app | None / No |
| Data safety | See below |
| Foreground service permissions | See below |

### Data safety

- **Does your app collect or share any of the required user data types?** **Yes**, only because of Google ML Kit (QR code scanning).
- **Is all of the user data collected by your app encrypted in transit?** Yes.
- **Do you provide a way for users to request that their data is deleted?** Data stays on the phone; deleting in the app or uninstalling removes it. Answer "No" to the account-deletion question, because there are no accounts.
- **Data types:** only **App info and performance › Diagnostics**:
  - Collected: **Yes**. Shared: **No**.
  - Processed ephemerally: No. Required or optional: **Optional** (only when you use **Scan QR code instead**).
  - Purpose: **Analytics** (ML Kit's own performance and error metrics).
- **Everything else** (location, personal info, files, photos, contacts, app activity, device IDs): **not collected**. Location permission is only used on the phone to read the Wi-Fi network name; nothing is stored or sent.

### Foreground service declaration

The app declares `FOREGROUND_SERVICE_CONNECTED_DEVICE` (`ActiveService`).

- **Task:** keeps the service timer, stage warnings and the connection to the LED sign and paired screens running while the operator's screen is off or another app is open, with Pause and Next on the lock screen.
- **Why the user would notice if it stopped:** the countdown on the LED sign and stage screens would stop updating and warnings would not fire during the service.
- **Video:** record 30–60 seconds on a phone: start a service, turn the screen off, show the lock-screen notification counting down and pressing Pause, and the Simulator or stage screen still updating. Upload it (for example as an unlisted YouTube video) and paste the link.

### Other permissions

- **Location:** foreground only, to read the Wi-Fi name for the LED sign. No background location, so no location declaration is needed.
- **Exact alarms:** the app asks for `SCHEDULE_EXACT_ALARM` (user-granted) for on-time warnings. It doesn't use `USE_EXACT_ALARM`, so no exact-alarm declaration is needed.
- **Camera:** QR scanning only.

## 6. Closed test (required for new personal accounts)

1. In **Testing › Closed testing**, create a track, add a Google Group (or an email list) with **at least 12 testers**, and promote the internal release to it.
2. Testers join with the opt-in link and install from Play. **At least 12 must stay opted in for 14 days in a row.**
3. Ask them to use it in a real rehearsal and send feedback from **Settings › About › Send feedback**.

## 7. Production

After the 14 days, **Apply for production** on the Dashboard and answer the questions about the closed test. Once approved, promote the tested release to **Production** (a staged rollout, for example 20 %, is a good first step).

## Every release after that

1. Merge the release PR, then tag `vX.Y.Z`. CI builds the `.apk` (GitHub and the guide site) and the `.aab` (Play), signed with the same key.
2. The version code comes from `pubspec.yaml` (`version: X.Y.Z+N`). `N` must go up with every upload; the release PR already does this.
3. Upload the `.aab` to a testing track, paste the release notes, then promote to production when it's been checked.
