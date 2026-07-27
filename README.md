# Fio

Fio is a private voice journal for iPhone. Speak or write an entry, keep the
original audio, and let the on-device observer notice what repeated, shifted,
or contradicted itself.

**Nothing leaves your phone unless you explicitly export it.** There is no
account, analytics, tracking, third-party SDK, application-owned network
service, or automatic sync. Recording, transcription, reflection, storage,
playback, and usage insights all happen locally.

## Inspiration

Fio was directly inspired by **Slate**, the voice-journaling app concept shared
by Eli Rousso in [this post on X](https://x.com/elirousso/status/2079594911637094442).
Fio is an independent, from-scratch implementation for iPhone, with its own
architecture, privacy model, interface, and feature set.

## What Fio does

- **Voice and text entries** — tap the microphone to record or hold it to
  write. Long recordings are saved incrementally as compact M4A files.
- **On-device transcription** — Apple Speech transcribes locally, with a
  selectable language and the option to transcribe an existing recording
  again in another language.
- **Original audio** — play, seek, and change playback speed without loading
  an entire long recording into memory.
- **Calendar timeline** — browse one day at a time, swipe between weeks, or
  jump directly to any date from 01/01/2000 through today.
- **Quiet reflection** — Apple Intelligence can add a short observation after
  an entry is stored. Model output is sanitized, and weak output stays silent.
- **Weekly read-back** — after activity on three or more occasions, Fio can
  summarize the completed week on Sunday.
- **Recurring topics and Dream** — an optional, on-device consolidation pass
  can notice connections across entries. Suggestions remain pending until they
  are accepted, renamed, or dismissed.
- **Private search** — search transcripts, reflections, context, and accepted
  topics through an in-memory index without sending a query off-device.
- **Private insights** — activity history, recording time, word count, active
  days, common hours, and current/longest streaks are calculated on-device.
- **Export** — share the transcript, original audio, or both using the system
  share sheet.
- **Encrypted backup** — manually export or import the complete journal and
  preferences with a one-time recovery phrase. This is not synchronization;
  backup files never contain the original audio recordings.
- **Appearance and language** — Light, Dark, or Automatic appearance; interface
  available in English, Portuguese (Brazil), and Spanish.

## Apple-native stack

| Layer | Technology |
| --- | --- |
| UI | Swift 6, SwiftUI, Liquid Glass |
| Recording | AVAudioEngine + incremental AAC/M4A writing |
| Transcription | SpeechAnalyzer + SpeechTranscriber |
| Reflection | Foundation Models / Apple Intelligence |
| Storage | SwiftData |
| Third-party code in the app binary | None |

The observer never chats, advises, or attempts therapy. It only reflects what
is already present in an entry. When there is nothing useful to add, it adds
nothing.

## Architecture

The repository uses **Fio** consistently across the app, Xcode target, Swift
package, bundle identifier, and GitHub repository:

```text
FioKit/                         Pure domain and application core
  Sources/FioKit/
    Domain/                       Entries, transcripts, calendar, reviews,
                                  reflection rules, usage statistics
    Application/                  Use cases and platform-independent ports
  Tests/FioKitTests/            Domain and application regression tests

Fio/                            iOS application shell for Fio
  Infrastructure/
    Audio/                        Capture, storage, playback, retranscription
    Intelligence/                 Foundation Models adapters
    Persistence/                  SwiftData records and repositories
    Background/                   Local Dream scheduling
    Performance/                  Opt-in Debug benchmarks
  Presentation/
    Screens/                      Timeline, recording, entry, insights, reviews
    AppPreferences.swift          Appearance and interface language
    JournalStore*.swift           Observable façade split by responsibility
    Theme.swift                   Adaptive G4 OS Clean-inspired palette

FioUITests/                     Deterministic critical-journey UI tests
```

The dependency rule is:

```text
Presentation → Application → Domain
Infrastructure → Application ports
```

`FioKit` imports no SwiftUI, SwiftData, Speech, or Foundation Models. Domain
rules and use cases stay independent from the iOS adapters. Persistence
mutations that span suspension points are serialized, and foreground
activation reloads authoritative local snapshots before background
maintenance resumes.

## Requirements

- Xcode 26 on macOS Tahoe
- iOS 26
- A physical iPhone for microphone and full on-device speech testing
- Apple Intelligence enabled for reflection and weekly read-backs

Fio still records, transcribes, stores, and plays audio on supported devices
without Apple Intelligence; only the reflection features remain silent.

## Run on an iPhone

1. Clone and open the project:

   ```sh
   git clone https://github.com/joaovitor2763/fio.git
   cd fio
   open Fio.xcodeproj
   ```

2. Select the `Fio` target, enable automatic signing, and choose
   your Apple development team.
3. Connect the iPhone, enable Developer Mode, and select it as the run
   destination.
4. Press `⌘R` and allow microphone access on first launch.

The display name, built product, target, repository, and bundle identifier all
use **Fio**. The application target uses `com.joaovitorsilva.fio`, and the
domain package is named `FioKit`.

## Tests

Run the platform-independent test suite and the critical UI journeys:

```sh
swift test --package-path FioKit
xcodebuild test \
  -project Fio.xcodeproj \
  -scheme Fio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FioUITests
```

Current status: **98 domain/application tests and 4 critical UI journeys, all
passing.** The UI suite covers search-to-detail navigation,
writing/saving/deleting an entry, Insights, Reviews, backup disclosure, and
recorder presentation.

## Performance

Fio includes an explicit Debug-only benchmark with a deterministic journal of
2,000 entries and 100 topics. Compared with the recorded baseline:

- journal refresh p90 improved from **459.4 ms to 209.3 ms**;
- first content ready p90 improved from **1,106.6 ms to 884.5 ms**;
- search p90 is **25.0 ms**, and saving entry context p90 is **48.8 ms**.

The fixture is opt-in, excluded from Release behavior, and does not add
analytics. See [PERFORMANCE.md](PERFORMANCE.md) for p50/p90/p99 results and
reproduction instructions.

## Privacy model

- Entries, transcripts, reflections, reviews, topics, Dream suggestions,
  metrics, and private M4A files are stored only on the iPhone.
- Encrypted backups are created only when requested, contain no M4A files, and
  go only to the location the author chooses through the system file picker.
- No account, device identifier collection, analytics SDK, or ad SDK exists.
- Fio has no application-owned networking code path.
- iOS may download Apple speech/model assets through system frameworks.
- Deleting an entry also deletes its associated audio file.

## Contributions

Fio is maintained as a personal project and is not accepting external
contributions. Please do not open pull requests; see
[CONTRIBUTING.md](CONTRIBUTING.md) for details. The Apache 2.0 license still
allows you to inspect, fork, modify, and redistribute the project under its
terms.

## License

Copyright 2026 João Vitor Chaves Silva.

Licensed under the [Apache License 2.0](LICENSE).
