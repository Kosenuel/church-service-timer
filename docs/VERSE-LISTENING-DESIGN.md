# Verse listening: feasibility and design

Status: study plus the engine-independent logic. **No speech engine is in
the app yet** and nothing here changes what the app does today.

The idea: the operator switches **Listen** on, the app hears the preacher
say "turn with me to John three sixteen" (or quote the verse without naming
it), and the passage appears in a **Ready** tray. The operator taps it to
send it to the screens. The app never puts anything on a screen by itself.

Everything stays on the device. No cloud speech service.

## 1. The answer in five lines

1. **Primary: sherpa-onnx** (Apache-2.0, `sherpa_onnx` Flutter package) with
   a small English **streaming Zipformer** model, run with **hotword
   biasing** towards the 66 book names, number words, "chapter" and
   "verse". It is the only candidate that is offline, streaming, supports
   both Android and Windows from Flutter today, and lets us bias the
   vocabulary.
2. **Fallback: Vosk** with a grammar restricted to references (small, very
   cheap, tolerant of a bad microphone because the grammar is tiny), but its
   Flutter package is stale (see 3.2), so it would need a fork or direct FFI.
   Second fallback, for quoted verses only: whisper.cpp re-checking short
   finished phrases.
3. **Not the platform recognisers.** Android's is built for short commands
   (it stops after a short pause and beeps) and its on-device mode is
   device-dependent; the Windows plugin uses the old SAPI dictation
   engine, marked beta by its own author, with no way to bias towards
   verses.
4. **Size:** about +11 MB compressed per Android CPU type for the engine
   (measured), about +23 MB uncompressed for Windows (measured), plus a
   model of tens of MB that should be **downloaded on first use**, not
   shipped. The only host needed is the one the app already uses for
   updates (GitHub releases), if we publish the model there.
5. **Honest expectation:** naming a reference ("John three sixteen") is
   plausible to catch most of the time from a clean sound-desk feed and
   noticeably less from a room microphone; accented speech in a reverberant
   room is the real unknown and can only be measured in the church. Quoted
   verses without naming them will work less often than references. See
   section 7.

## 2. What I could and could not check

Reached and read: pub.dev package metadata, READMEs, changelogs and source
archives for `speech_to_text`, `speech_to_text_windows`, `vosk_flutter`,
`sherpa_onnx` (and its per-platform native packages, whose library sizes I
measured by unpacking them), `record`; the READMEs of whisper.cpp,
sherpa-onnx and vosk-api and the sherpa-onnx Flutter example, through
`raw.githubusercontent.com`.

**Not reachable from this machine:** `huggingface.co`, `github.com`
release pages and downloads, `k2-fsa.github.io` (sherpa-onnx docs and model
lists), `alphacephei.com` (Vosk models and docs), Microsoft and Android
developer documentation. So:

- I did **not** download or run any speech model. No accuracy or speed
  figure for any engine in this document was measured by me.
- Model file sizes for sherpa-onnx and Vosk, word error rates, phone CPU
  figures, and the Windows/Android platform recogniser behaviour beyond what
  the plugin source shows are **from memory and marked (unverified)**.
- The sizes marked (measured) are real: unpacked from the pub.dev archives.

## 3. Engine options

### 3.1 The platforms' own recognisers

**Android `SpeechRecognizer`** through `speech_to_text` 7.5.0 (BSD-3,
published 2026-09-14; Android, iOS, macOS, web, Windows).

- Offline: the plugin source calls `createOnDeviceSpeechRecognizer` and sets
  `EXTRA_PREFER_OFFLINE` when `onDevice` is asked for (verified in source).
  Whether a given phone has an offline English model installed, and how good
  it is, depends on the phone and Google's speech service (unverified).
- Continuous listening: the plugin's own README says it is "designed for
  commands and short phrases, not continuous spoken conversion or always on
  listening", that "Android speech recognition has a very short timeout when
  the speaker pauses ... none had a pause longer than 5 seconds ... no way
  to change that", that the system **beeps** on start and stop with no
  supported way to turn that off, and that there is "not yet a way to achieve
  [continuous recognition] using the Android or iOS speech recognition
  capabilities". Restarting the recogniser in a loop loses words at each
  restart, and the beeps would be heard through the church speakers if the
  phone is near the sound system. This disqualifies it for sermon listening.
- Biasing: none for books or numbers (Android 13+ has a contextual
  biasing option in the API, unverified; not exposed by the plugin).
- Size and cost: nothing added to our download; the model belongs to the
  phone.

**Windows**: `speech_to_text` 7.5.0 pulls in `speech_to_text_windows` 1.0.1.

- Its C++ source (read) uses the legacy **SAPI** interfaces (`ISpRecoGrammar`,
  `LoadDictation`, `SetDictationState`), not `Windows.Media.SpeechRecognition`.
  The plugin changelog says Windows support "is currently in beta ... there
  are known issues and this is not yet ready for production use".
- SAPI dictation uses the older desktop recogniser, usually needs the user to
  have set up speech recognition and a microphone in Windows, and is not
  known for accuracy on accented speech (unverified, from memory).
- `Windows.Media.SpeechRecognition` supports list and grammar constraints
  that would work offline, and a "dictation topic" constraint that, in my
  memory, sends audio to Microsoft's online service unless the user has an
  offline language pack (unverified). No Flutter plugin I could reach uses
  it; we would have to write a C++/WinRT plugin ourselves.
- Verdict: not a base for this feature.

### 3.2 Vosk

- Licence: Apache-2.0 (vosk-api README, pub tag for `vosk_flutter`).
- Offline, streaming, small models. The vosk-api README says "models are
  small (50 Mb)" and "reconfigurable vocabulary". The Dart bindings expose a
  `grammar` list of phrases to `createRecognizer` (verified in the package),
  which restricts recognition to those phrases: an attractive fit for
  "book + number + verse" if the grammar is generated for all 66 books and
  all chapter/verse numbers.
- Flutter: `vosk_flutter` 0.3.48 lists Android, Linux and Windows, loads a
  model zip from assets. **But it was published 2023-04-07 and its pubspec
  says `sdk: >=2.15.1 <3.0.0`**, so a Dart 3 app (ours is `>=3.10.0`) cannot
  depend on it as published. `vosk_flutter_service` 0.1.3 (2026-09-05, a
  third-party fork by another author, lists all platforms) exists; I did not
  review its code or maintenance beyond metadata. Maintenance risk: high.
- Accuracy: a restricted grammar is robust on a noisy input because the
  recogniser can only answer with reference-shaped phrases; the cost is that
  it answers with *something* reference-shaped for any speech, so the
  false-positive handling in the spotter becomes more important. A small
  general model is usually clearly worse than the newer transducer models on
  accented speech (unverified). An Indian-English Vosk model exists
  (vosk-api README lists "Indian English"); no Nigerian one.
- Model: ~40-50 MB for the small English model (unverified), shipped as an
  asset zip or downloaded.
- CPU/RAM: low; the small models run well on old phones (unverified).

### 3.3 sherpa-onnx (recommended)

- Licence: Apache-2.0 (pub tag). Package `sherpa_onnx` 2.0.3, published
  2026-11-22, 127 likes and about 114,000 downloads in 30 days at the time
  of reading. Very actively maintained (the changelog has dozens of changes
  per release).
- Flutter support (verified from pubspec, README table and the native
  packages): Android (arm64-v8a, armeabi-v7a, x86, x86_64), Windows (x64,
  arm64), iOS, macOS, Linux, web. Pure `dart:ffi` bindings over prebuilt
  libraries, so no plugin build step beyond fetching the packages.
- Features present in the Dart API (verified in the source): streaming
  `OnlineRecognizer` (transducer, Zipformer2-CTC, paraformer, NeMo CTC),
  offline recogniser (Whisper and others), `KeywordSpotter`, voice
  activity detection, and for the online recogniser `decodingMethod`
  (`modified_beam_search`), `hotwordsFile` and `hotwordsScore`.
- **Hotword biasing**: with `modified_beam_search`, a hotwords file (one
  phrase per line, optional per-phrase boost) raises the score of those
  words while decoding. The README lists a third-party Android app that
  "boosts the words of the script as hotwords with modified beam search"
  using the English streaming Zipformer `en-2023-06-26` on the phone, so the
  combination works on a phone in practice. Hotwords raise the chance of the
  right word; they do not stop it hearing other words, which is what we
  want. (For the BPE-based English model the hotwords need the BPE
  vocabulary; for others a character/word form; how exactly is in the
  docs I could not reach.)
- **Keyword spotting** (`KeywordSpotter`) is a separate, cheaper mode for
  fixed phrases. It fits "the 66 book names" less well than hotwords on a
  full recogniser (it only reports keywords, not the numbers that follow),
  so I would use the full recogniser with hotwords, and the keyword spotter
  only as a possible low-power "wake" stage later.
- Size added to the download (measured by unpacking the pub packages,
  uncompressed library bytes, with the compressed package size from
  pub.dev in brackets):

  | Platform | Libraries (uncompressed) | Package download |
  |---|---|---|
  | Android arm64-v8a | 27.9 MB (onnxruntime 22.2, sherpa 5.2, C++ API 0.4) | 10.8 MB |
  | Android armeabi-v7a | 19.4 MB | 9.8 MB |
  | Android x86_64 | 31.8 MB | 11.8 MB |
  | Windows x64 | 22.9 MB (onnxruntime.dll 17.8) | 17.2 MB (this package holds x64 and arm64 together) |

  The Android release workflow runs plain `flutter build apk --release`
  (no ABI split), so the universal APK would carry arm64, armv7 and x86_64:
  roughly **+30 MB** on the 92 MB APK (the packages above, summed; the real
  figure after Flutter's own compression may differ). An app bundle for
  Play, or `--split-per-abi`, would cost each phone only its own ABI (about
  +10 MB). Windows: the x64 DLLs are 22.9 MB uncompressed; after the
  installer's compression I would expect roughly +7 to +10 MB on the 16 MB
  installer (unverified estimate).
- Models: published by the sherpa-onnx project as release assets
  (`https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models`, named in
  the Flutter example's README, verified) and on Hugging Face. Sizes
  (unverified, from memory): English streaming Zipformer int8 models are
  roughly 20 to 120 MB depending on the model, with the 2023-06-26 English
  Zipformer's int8 encoder around 70 MB and a small "20M" variant around
  40 MB in total. Whisper tiny.en/base.en ONNX int8 exports are also
  available through the same project (sizes unverified).
- CPU/RAM: streaming Zipformer int8 runs faster than real time on a single
  big core of a mid-range arm64 phone (unverified; my memory is a real-time
  factor of roughly 0.1 to 0.3), and a few hundred MB of RAM at most for the
  small models (unverified). To be measured in phase 1.
- Latency: streaming; chunk sizes of 16 frames (about 0.3 s) in the Zipformer
  models named "chunk-16" (the file names in the Flutter example, verified),
  so words appear within about half a second of being said.
- Accented English: the public English streaming models are trained on large
  general English corpora (my memory: LibriSpeech and GigaSpeech; unverified).
  Nothing in the model targets Nigerian English. I expect worse accuracy
  than on American English, and worse still in a reverberant room. The
  spotter is built for that (section 5), and the accent-aware spelling for
  "th" said as "t" ("tree" for three) is already in it.
- Maintenance risk: low; the project is large and releases often. Risk to
  watch: the Dart API is young and changes between versions.

### 3.4 whisper.cpp

- Licence: MIT (verified in the repository). Offline, C/C++.
- Sizes (README table, verified): tiny 75 MiB, base 142 MiB, small 466 MiB
  on disk; memory about 273 MB, 388 MB and 852 MB. Quantised models
  (`-q5_0`) are smaller.
- **Not streaming by design.** The repository's own `stream` example "is a
  naive example ... samples the audio every half a second and runs the
  transcription continuously", re-decoding a sliding window. That multiplies
  CPU, produces unstable partial text, and Whisper is known to invent text
  on silence or noise (unverified, widely reported).
- Flutter: `whisper_flutter_new` 1.0.1 (2024-06-12) lists Android, iOS and
  macOS only; **no Windows**. I found no maintained Flutter plugin covering
  both. sherpa-onnx can run Whisper models through its offline recogniser,
  which gives a Windows and Android route to the same models.
- Vocabulary biasing: an initial text "prompt" can nudge Whisper towards
  names (unverified), but not a hard restriction.
- Strengths: the best general robustness to accents and noise of the four
  (unverified). That makes it the right tool for a *second look at a
  finished phrase*, not for live listening.
- Verdict: not the live engine; keep as an option for re-checking phrases
  where the spotter was unsure (phase 4).

### 3.5 Side by side

| | Android on-device | Windows (SAPI plugin) | Vosk | sherpa-onnx | whisper.cpp |
|---|---|---|---|---|---|
| Licence | BSD-3 plugin; OS service | same | Apache-2.0 | Apache-2.0 | MIT |
| Offline | partly, device dependent | yes | yes | yes | yes |
| Android in Flutter | yes | n/a | yes (stale package) | yes | yes (one plugin, 2024) |
| Windows in Flutter | n/a | beta | yes (stale package) | yes | no plugin found |
| Continuous listening | no (short pause stops it, beeps) | dictation, beta | yes | yes | no (pseudo-streaming) |
| Added to download | 0 | 0 | model 40-50 MB (unverified) | engine +10 MB/ABI and +23 MB Windows (measured), model separate | model 75 MB+ |
| Bias to our words | no | no | grammar list (hard restriction) | hotwords (soft boost) | prompt (weak) |
| Accented English | unknown | unknown, probably weak | probably weak | unknown, test needed | probably best |
| Maintenance risk | low | high (beta) | high (Dart 2 package) | low | medium (no Flutter plugin) |

## 4. Recommendation

**Primary: sherpa-onnx, streaming English Zipformer (int8), with hotwords.**
Hotwords: the 66 book names as said, their common mishearings (the same
table the spotter uses), "chapter", "verse", "verses", and the number words.
Feed the transcripts to the spotter in section 5. If hotwords alone are not
enough on real recordings, the next step is to fine-tune the choice of model
(there are several English streaming models; testing which handles Nigerian
English best is phase 1 work), not to change engine.

**Fallback: Vosk with a reference grammar**, because a restricted grammar
can survive a poor microphone and a noisy room better than a general model.
It would need either a fork of `vosk_flutter` (move its SDK constraint) or
our own thin `dart:ffi` binding to the C library, which is what the package
is anyway. I would only do this if sherpa-onnx does badly in phase 1 *and*
Vosk does better on the same recordings; test both on the same audio before
building either.

### Model: download on first use, not in the app

A 40-120 MB model would double the Android download for every user, most of
whom will never switch Listen on. Put the model behind **Settings, Verse
listening, Download (about N MB)**.

- The app already reaches GitHub for updates: the code uses
  `api.github.com` and `github.com/ImmanuelOkose/church-service-timer-guide/releases`.
  The simplest and most private route is to **publish the chosen model file
  as an asset on a release of that same repository** (one extra release
  asset, which also pins exactly the model we tested) and download from
  there with a SHA-256 check built into the app. Hosts that must be allowed
  then are the ones the updater already needs: `github.com` and the host
  GitHub redirects release assets to (currently `objects.githubusercontent.com`
  or `release-assets.githubusercontent.com`; I could not confirm which from
  here, so check it in the church's network).
- Downloading straight from the sherpa-onnx project instead needs
  `github.com` (+ the redirect host above) for its release, or
  `huggingface.co` and its CDN hosts (`cdn-lfs.huggingface.co`,
  `cas-bridge.xethub.hf.co`; unverified). I do not recommend depending on
  somebody else's file names staying put.
- Allow the download over Wi-Fi only by default, resumable, with progress,
  and a delete button. After it, Listen needs no network.
- Windows: same file, same place, kept under the app's data folder.
- Alternative for churches with no internet at all: import the model file
  from a USB stick or from another device already running the app
  (the app already pairs devices; sending a 50 MB file over that link is
  possible but is extra work, not part of version one).

### Getting audio in

Use the `record` package (7.2.0, published 2026-11-11, Android, Windows,
iOS, macOS, Linux, web). Its source shows `startStream(RecordConfig)` for raw
PCM, `listInputDevices()`, `hasPermission()` and amplitude reading (for the
level meter).

- **Android**: add `RECORD_AUDIO` to the manifest (today the manifest has
  camera and network permissions but no microphone permission). Ask when the
  operator first switches Listen on, with a plain-words reason. Use
  16 kHz mono PCM16 (what the models want). To use a USB audio interface or
  a headset line-in the operator picks it from the same device list
  (the package lists device selection as supported on Android, with
  version caveats I did not check). Keeping the microphone open when the
  app is not in front needs a foreground service of type microphone on
  recent Android (unverified); version one should simply require the app to
  stay in front with the screen on (section 6).
- **Windows**: `record` uses Windows MediaFoundation. `listInputDevices()`
  lists capture devices, so "Line In (Realtek)" or a USB mixer shows up by
  name and the operator chooses it. The feature table in the package shows
  no permission-check support on Windows; Windows 10/11 can still block
  desktop apps from the microphone in **Settings, Privacy, Microphone**, and
  the app can only find out by getting silence or an error, so the "no
  sound" state must point at that setting (section 6).
- A sound-desk feed is better than the device microphone in every way that
  matters to a recogniser (no room echo, direct voice). Recommend the line
  feed first in the guide and in the Listen settings text.

## 5. The engine-independent logic (built and tested)

`lib/domain/verse_spotter.dart` (no audio, no Flutter, only
`bible.dart`), tests in `test/lyrics/verse_spotter_test.dart`.

### 5.1 `VerseSpotter`: spoken references

`hear(text, isFinal:, at:)` takes recogniser output (partial transcripts
that replace each other, and final ones that are kept) as lower-case words
without punctuation, and returns only **new** candidates:
`VerseCandidate { reference, label ("John 3:16"), heardAs, confidence,
provisional, correction, openEnded, replaces, alternatives }`.

How it decides:

- A **book** is found by a table of how books are said and mis-heard
  (about 185 entries): "romance"/Romans, "axe"/Acts, "look"/Luke,
  "sums, palms"/Psalms, "almost"/Amos, "dude"/Jude, "mica"/Micah,
  "jose"/Hosea, "efficient"/Ephesians, "philipines", "he brews",
  "is equal"/Ezekiel, "i say a"/Isaiah, "tight us"/Titus, "roof"/Ruth,
  "revelations", "first king", "song of songs", and so on. Numbered books
  ("first/second/third john", "second corinthians", digits, or "one/two/
  three") are handled, and a numbered book said with no number
  ("corinthians thirteen four") is reported as the first with the others in
  `alternatives`.
- Each book has a **weight**: distinct names (Habakkuk) are strong; names and
  ordinary words (john, mark, job, numbers, acts, judges) are weak; mishearings
  that are themselves ordinary words (look, axe, sums, almost, roof) are
  weakest. A weak book needs more evidence: a lead-in ("turn with me to",
  "let us read", "the book of", "as it says in", "our text is" ...), or the
  words "chapter"/"verse", or both a chapter and a verse. So "mark three
  sixteen" is reported, but "mark my words", "the job of a pastor",
  "numbers don't lie" and "john went to the market" are not.
- **Numbers**: digits, "three sixteen" (chapter and verse run together),
  "twenty three" as the chapter (with 20:3 offered as the alternative),
  "one hundred and nineteen verse one oh five", "one nineteen" for Psalm 119,
  "verses four to seven", "sixteen and seventeen", "from verse one",
  "john 316". The run of number words after the book is split into chapter
  and verse using what the book really has.
- **Validation against the Bible**: a chapter that does not exist in the book
  drops the candidate; a verse that does not exist cuts it back to the chapter
  and lowers the confidence ("john three sixty five" gives John 3 at lower
  confidence; "romans seventeen" gives nothing; "psalm two hundred" gives
  nothing).
- **Streaming**: the same words are rescanned on every transcript, so a
  reference can arrive across partials ("turn to john", "turn to john three",
  "turn to john three sixteen") or across finals ("...to john" then "three
  sixteen"). A candidate that runs to the end of a partial is `provisional`;
  when more words complete it, the new candidate carries `replaces` (the old
  one's key) so the tray replaces it instead of piling up. A provisional one
  that the final transcript settles is reported once more, settled.
- **Corrections**: "john three sorry john four" and "romans eight twenty
  eight sorry twenty nine" are reported as corrections with `replaces` set.
- **De-duplication**: the same reference within 30 seconds (configurable) is
  reported once; a different reference never waits.
- **Sensitivity** is `minConfidence` (default 0.55): the setting maps to
  roughly 0.65 / 0.55 / 0.45 for low / normal / high.

Accent handling so far: "tree, tirty, tirteen, tird" are read as
three, thirty, thirteen, third inside reference spotting. Homophone number
errors ("for" for four, "to" for two, "won", "ate") are **not** mapped: "to"
is also the range word and "for"/"ate" are common, and guessing wrongly would
create false references. Whether to add them depends on what a real engine
does on real recordings.

### 5.2 Overlap with `fix/forgiving-bible-references`

That branch adds spoken-form parsing to `parseBibleReference`. I did not
edit `bible.dart`. The overlap is the number-word handling: in
`verse_spotter.dart` it is `parseSpokenNumber`, `_impliedHundred` and
`_runEnd` (the "chapter and verse run together" splitting is `_chooseSplit`,
which needs the Bible and the streaming context and is unlikely to move). When
that branch lands, `parseSpokenNumber` should become a call to its parser (or
its parser should be exported and used here), and the tests in the "spoken
numbers" group (they pin 1 to 176 round trip and the "oh"/"hundred and"
forms) should be kept as a check that both agree. The book-name table here is
deliberately *wider* than `_bookNames` in `bible.dart` (it holds mishearings,
not abbreviations), so it should stay in this file.

### 5.3 `VerseMatcher` and `QuoteSpotter`: quoted verses

`VerseMatcher(bible).match(words)` finds the verse a run of recognised words
is quoting. Words are put in a rough canonical form (so "loveth", "loves" and
"loved" are one word, and thee/thou/ye, thy/thine, hath, doth, saith, unto,
shalt, wilt, art, wherefore, verily, whosoever become their modern forms), a
rare-word index shortlists verses, and the shortlist is scored by a weighted
longest-common-subsequence (rare words count more). Each candidate gets:

- `score` 0 to 1: how well the heard words fit the verse, counting dropped,
  wrong and extra words against it;
- `evidence`: the weight of the words matched (long and rare-word matches are
  stronger than short ones);
- `coverage`: the share of what was heard that the verse accounts for.

A **proposal** is made only when evidence, score and coverage are all above
their thresholds **and** the best is at least 1.25 times the runner-up. Verses
that exist twice (the Gospel parallels, Kings/Chronicles, the many "grace of
our Lord Jesus Christ be with you" endings) are therefore *not* proposed, but
all the candidates are returned so the tray could offer them.
`QuoteSpotter` keeps a rolling window of the last 24 words and reports each
verse once per minute.

Thresholds (`minEvidence` 16, `minScore` 0.55, `minCoverage` 0.4, `lead`
1.25) were chosen on a **tuning seed** (grid of evidence 12/14/18/22,
coverage 0/0.4/0.5/0.6, lead 1.15/1.25/1.5; 14 and 18 gave the same result,
so 16 is the midpoint, not itself a grid point) and the figures below are
from a **different seed**, so they are not fitted to the test set. The
sentence lists are mine, partly seen while tuning.

Test set (in the test file, regenerated from fixed seeds): 600 real KJV verses
of at least 8 words per row, a random span of 12 to 24 words from each, each
word corrupted with the stated probability by dropping it, replacing it with a
random Bible word, or adding a random word before it, equally likely; the
"modern" rows also change archaic words to modern ones with probability 0.6
(thee/thou/ye to you, thy to your, hath to has, unto to to, saith to says,
behold to look or see, whosoever to anyone, begotten to "one and only" ...).
Negatives: 375 sentences of ordinary church talk including sermon-style
sentences built from Bible vocabulary.

| Words | Errors | Right | Wrong verse | Abstained | Precision |
|---|---|---|---|---|---|
| KJV | 0% | 94.2% | 1 | 34 | 99.8% |
| KJV | 10% | 87.7% | 1 | 73 | 99.8% |
| KJV | 20% | 67.8% | 1 | 192 | 99.8% |
| KJV | 30% | 42.7% | 0 | 344 | 100% |
| modern | 0% | 93.5% | 1 | 38 | 99.8% |
| modern | 10% | 88.0% | 0 | 72 | 100% |
| modern | 20% | 70.8% | 0 | 175 | 100% |
| modern | 30% | 46.5% | 0 | 321 | 100% |
| modern, 20%, with 6 to 11 words of other talk first | | 57.7% | 0 | 254 | 100% |

False positives on the 375 non-Scripture sentences: **0**. (While building the
set, nine sentences I had written as "not Scripture" did produce a proposal.
Six were real quotations or close paraphrases, for example "the Lord bless you
and keep you" (Numbers 6:24) and "what does it profit a man ..." (Mark 8:36),
so the matcher was right and I removed them from the negative set. One, "the
love of God is greater than anything we can think of" (1 John 3:20), was a
genuine false positive from a few matching words inside other talk; the
coverage rule fixed it and it is now a fixed negative.)

Reading the table: the "abstained" cases are mostly correct refusals:
word-for-word parallel passages, and heavily corrupted or short windows. The
matcher does not guess. The 0%-error recall is under 100% because of
parallel passages and short or very common spans (below the evidence bar).

Query latency over all 31,102 verses (20-word window, 300 queries at 20%
errors, `flutter test` on this shared build machine, JIT, not a phone): mean
0.5 ms, p95 0.8 ms, worst 6 ms. Building the index took about 0.85 s once.
A phone will be slower, but even 10 to 20 times slower is negligible beside
the recogniser. (The index's memory use was not measured.)

**Limits of this evaluation, plainly:** the error model is uniform random;
real recogniser errors are phonetically similar words and come in bursts
(a whole phrase lost to reverb), which may be better or worse. It matches
**the KJV only**: a preacher reading from NIV, ESV, NKJV or NLT (very likely
in many churches) will mostly be *not* recognised, since the words differ
(the "modern" rows only change some archaic words, not translation
differences). A modern-translation matcher would need those texts
(public-domain WEB or ASV could stand in; licensed ones cannot be bundled)
and is out of scope here.

## 6. What a first version would be

### User flow

- **Slides page:** a **Listen** switch (off every time the app starts; never
  remembered as on). Next to it: a level meter (so the operator can see sound
  is arriving) and the input name.
- **Ready tray** under the switch (one row per candidate, newest first,
  at most five, old ones fade after a few minutes):
  `John 3:16 · KJV` with "Heard: turn with me to john three sixteen",
  a small confidence mark (provisional ones dimmed), and one big **Send**
  button. Tapping the row opens the verses in the normal Slides preview so the
  operator sees them before sending. Dismiss with a swipe or an X. For a
  candidate with `alternatives`, a "Or Psalm 20:3" link.
- **Never automatic.** Nothing reaches a screen except by the operator's tap on
  Send (the same action as sending a verse today). Candidates that arrive
  while the operator is busy only add rows; they do not steal focus, make a
  sound, or replace what is on the screens. A `replaces` candidate replaces the
  row, not the screen.
- Candidates that fail validation never appear; the operator is never shown a
  chapter that does not exist.

### Settings (Settings, Verse listening)

- Listening engine status and **Download model (about N MB)** / **Delete**.
- **Input device** (list from the platform; "Default microphone" first).
- **Sensitivity:** Fewer suggestions / Normal / More suggestions
  (`minConfidence` about 0.65 / 0.55 / 0.45).
- **Also listen for verses read aloud** (the quote matcher), off by default
  in version one.
- State is on this device only and not in backups, following the `autoUpdate`
  / `seenVersion` pattern (and absent from `exportBackup`).

### Privacy wording (draft)

> **Listening stays on this device.** When Listen is on, the sound is turned
> into words inside the app and thrown away straight away. The app does not
> record, save or send the sound or the words. It keeps the last minute or so
> of words in memory to find Bible references, and forgets them when you switch
> Listen off or close the app. The only time this feature uses the internet is
> to download its speech file once, from GitHub.

(That wording is a promise: the implementation must not write transcripts to
disk or to logs. A support log may record *that* a reference was heard and
whether it was sent, never the words.)

### Battery, CPU and "Keep screen awake"

- A streaming recogniser works continuously: I expect one or two CPU cores at
  light to moderate load while Listen is on (unverified; to be measured), so
  noticeable battery use and some heat on a phone, nothing on a plugged-in PC.
  Advice: use a tablet or phone on charge, or a PC.
- Android blocks microphone use from a backgrounded app on recent versions
  unless it runs a foreground service (unverified for each version), so
  version one **requires the app in the foreground with the screen on**. The
  interaction with the existing setting: when Listen is switched on and
  **Keep screen awake** is "never", offer to keep the screen awake while
  listening ("Listening needs the screen on. Keep it awake while Listen is on?
  Yes / No") rather than silently overriding the setting, and switch Listen off
  (with a notice) if the app goes to the background and the platform stops
  the microphone. On Windows, Listen continues while the window is behind
  others, but a sleeping PC stops it, so the same offer applies.
- Run the recogniser off the UI isolate (a worker isolate over FFI) so
  the timer and clocks never stutter.

### Failure states (what the operator sees, in plain words)

| Situation | What is shown |
|---|---|
| No microphone permission (Android) | "Allow the microphone to use Listen." Button to ask again or open the app's permission page if blocked. |
| Windows blocks desktop microphone access, or no sound for 10 s while the meter is flat | "No sound is reaching the app. Check the input in Settings, or Windows Settings, Privacy, Microphone." |
| Model not downloaded | Listen is off with "Download the listening file first (about N MB)". |
| Download failed or checksum mismatch | "Could not download. Try again on Wi-Fi." File deleted; nothing half-installed is ever loaded. |
| Not enough space | "Needs N MB free." |
| Engine will not load on this device (old CPU/OS, no library) | "Listening is not available on this device." The Listen switch is hidden or disabled with that sentence, and the rest of the app is unaffected. |
| Too slow (the recogniser falls behind real time) | "This device is too slow to keep up." Listen turns itself off rather than showing late suggestions. |
| Device disconnected (USB mixer unplugged) | Listen pauses, "Input lost", the Ready tray keeps what it had. |
| Another app has the microphone | "The microphone is in use by another app." |

### How it will be tested without a real sermon

1. **Pure logic** (done): the 187 hand-written spoken-reference cases, a round
   trip of 702 chapter/verse readings over all 66 books, the streaming
   behaviours, and the quote matcher evaluation.
2. **Engine on recorded speech**, as a command-line harness in phase 1
   (a Dart script that reads a WAV, runs the engine, prints transcripts and
   the spotter's candidates), scored automatically against a list of what was
   said:
   - Public-domain Bible readings: LibriVox publishes public-domain recordings
     including readings of the King James Bible (unverified: not reachable from
     here; check the licence on each recording). Good for the quote matcher and
     clean-speech references, not for accent.
   - Accented speech: datasets with Nigerian English exist (from memory:
     Mozilla Common Voice has an accent tag and is CC0; AfriSpeech-200 is
     Nigerian-accented but, I believe, under a non-commercial licence;
     OpenSLR has a crowdsourced Nigerian English set; **all unverified**, none
     reachable from here). Non-commercial licences are fine for internal
     testing, never for bundling.
   - **Synthetic references**: text-to-speech with several voices saying
     "turn to john three sixteen" and 200 random references, mixed with
     room-reverb impulse responses and noise. Cheap to make, fully labelled;
     it tests the whole chain but not accent.
   - **The church's own audio** is far more valuable than any of these:
     recordings of a few real services (with the pastor's permission,
     kept on the owner's devices, never uploaded), which the owner or a
     volunteer labels with the references actually said. Even 30 minutes
     would show far more than the public sets.
3. **UI**: golden tests for the Listen switch and Ready tray at the standard
   sizes, with a fake engine that emits scripted transcripts (the spotter is
   engine-independent so the UI can be tested with no audio).

**What only a beta in the church can show:** how the recogniser copes with
this room's echo, with each preacher's accent and pace, how often people
actually say references the way the spotter expects (do they say "John three
sixteen" or "John chapter three and verse sixteen" or say the verse number
only later?), what the sound-desk feed sounds like by the time it reaches
a phone, battery life over a two-hour service, and above all how many
suggestions the operator finds useful versus noise. The beta should keep a
local, content-free counter: suggestions shown, sent, dismissed.

### Phases

0. **This work:** feasibility and the pure-Dart logic.
1. **Engine bake-off (no app changes):** a command-line harness; sherpa-onnx
   models (and Vosk with a grammar, and whisper small as a reference) on the
   same recordings; choose model and hotword score; measure real-time factor
   and memory on a mid-range Android phone and a Windows PC. Decision gate: go
   or no-go on accuracy for the church's own audio.
2. **Plumbing behind a hidden switch:** `record` capture, engine in a worker
   isolate, model download with checksum, Listen switch, level meter, Ready
   tray, settings, failure states, tests, guide text. References only.
3. **Church beta:** a few services with an operator who is told it is
   experimental; counters; tune hotwords, thresholds and the confusion table
   from what was actually misheard (the table is just data).
4. **Quoted verses** (KJV only at first), then optionally a second look with
   a larger model on short finished phrases, then other translations if there
   is a licence-clean text.

### How well will it work? (an honest estimate)

This is a judgement, not a measurement.

- **Spoken reference with a clean line feed from the desk and a good model
  with hotwords:** I would hope to catch most of them (perhaps 6 to 8 in 10,
  the exact book, chapter and verse), with a further share landing as "close"
  (right book and chapter, wrong or missing verse), which is still useful in
  a tray the operator checks before sending. Numbers are the weak point:
  short words that sound alike, said fast, in an accent where "three" may be
  "tree" and with no help from context.
- **Same from a phone or tablet microphone across a reverberant room:**
  clearly worse; I would not be surprised by 3 to 5 in 10, with a lot of
  noise in the tray at a sensitive setting. Reverb is hard for every
  recogniser, and the accent difference adds to it.
- **A quoted verse without its reference:** only when the preacher reads in
  the KJV, reads whole phrases, and the recogniser keeps most words: I would
  expect it to work for famous verses read slowly and to abstain otherwise.
  The synthetic tests say the *matching* is solid up to about 20% word errors;
  they say nothing about how often the real engine stays under that.
- **False suggestions:** the design keeps them cheap (a tray row, never a
  screen), and the validation cuts the impossible ones, but a busy sermon
  that mentions "John" and numbers will produce a few. The sensitivity setting
  exists for this.
- It is realistic as an **operator assist** (saves the operator typing or
  searching when it works, costs a glance when it does not). It is not
  realistic as something the operator can stop watching.

## 7. Open questions for the owner

1. **Which Bible do your preachers read from?** The matcher only knows the KJV;
   if most read NIV/ESV/NLT, quoted-verse matching will rarely fire, and the
   value is in references only.
2. **Where will the sound come from in practice?** A line feed from the
   mixer (best), or the operator's phone or tablet in the room? This changes
   the expected accuracy more than any engine choice.
3. **How do your preachers announce a passage?** "John three sixteen",
   "turn to John chapter three", or "John three and verse sixteen"? Examples
   from real services would sharpen the spotter more than anything.
4. **Can we record a few services** (only for testing, kept on your devices)
   and have someone note the references said? Thirty minutes of the actual
   room would settle the engine question.
5. **Is a one-time download of tens of MB acceptable** at the church (and may
   the model be published on the same GitHub release page as the app)? Or
   does it have to install from a USB stick?
6. **Android in the background:** is it acceptable that Listen needs the app
   in front with the screen on (version one), or does it have to keep going
   with the screen off?
7. **Which devices** are the real targets (model of the Android phones or
   tablets, and the Windows PCs' age)? Speed and memory on the oldest one
   decides how large a model is possible.
8. **Does the app still ship a fat universal APK?** The engine adds about
   30 MB to that; if you move to per-ABI downloads it is about 10 MB per
   phone.
