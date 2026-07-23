# Slate

A voice journal built on one rule: **nothing leaves your phone.**

You speak your mind and Slate writes it down. It notices patterns and reads
your week back to you in a summary every Sunday.

There's no account. No analytics. No tracking. No third-party SDKs. No
network calls. The app is private because there is nothing to collect. Turn
on airplane mode and everything still works. There's no server.

## 100% Apple, top to bottom

| Layer | What it runs on |
| --- | --- |
| Transcription | `SpeechAnalyzer` + `SpeechTranscriber`, on device |
| Reflection | The ~3B-parameter Apple Intelligence model via FoundationModels, on the Neural Engine |
| Storage | SwiftData |
| UI | Swift 6, SwiftUI, Liquid Glass |
| Third-party code in the binary | None |

The local model is an **observer**. It never replies, advises, or comforts.
It reads an entry and writes down only what is already there — what
repeated, what contradicted itself, what shifted. When it has nothing real
to say, it says nothing.

## The app

- **Record** — a waveform, a clock, pause, done. A soft 3-minute cap you can
  extend 30 seconds at a time (never past 10 minutes). Recording auto-finishes
  when time runs out.
- **Timeline** — your days, newest first, under a Monday-first week strip.
  Each card shows the observer's one-line reading (or your own opening words
  while it reads, marked with a soft pulse) and its topic tags.
- **Entry** — the observations, the tags, the full transcript. If the reading
  is off, add context in your own words; the observer reads that too. Re-record
  or delete from here.
- **Review** — on Sunday, Slate reads the week back to you: a title, a
  sparkline of minutes spoken per day, and one or two plain paragraphs about
  what happened. Weeks need entries on 3+ occasions to earn a review.

## Architecture — Domain-Driven Design

The project is split into a pure domain core (`SlateKit`, a Swift package
with **zero dependencies beyond Foundation** — it builds and tests on macOS,
Linux, and iOS) and a thin iOS shell that plugs platform frameworks into the
domain's ports.

```
SlateKit/                          ← the domain core (tested, platform-free)
  Sources/SlateKit/
    Domain/
      Entry.swift                  Aggregate root: one spoken entry
      WeekReview.swift             The Sunday read-back
      Transcript.swift             Value object: the words as spoken
      Reflection.swift             Value object: observer output + sanitization rules
      RecordingBudget.swift        Value object: the 3-minute soft cap policy
      JournalCalendar.swift        Domain service: Monday-first weeks
      ReviewPolicy.swift           Domain service: when a week earns a read-back
      TimelineBuilder.swift        Domain service: day grouping
      SpeakingWeek.swift           Domain service: sparkline minutes
      Formatting.swift             Testable display formats ("1:53", "Mon July 13th, 2026")
    Application/
      Ports.swift                  EntryRepository · ReviewRepository ·
                                   ReflectionService · WeekSummaryService
      RecordEntryUseCase.swift     Finished recording → stored entry
      AnnotateEntryUseCase.swift   Observer reads one entry (sanitized, silence-safe)
      AmendEntryContextUseCase.swift
      DeleteEntryUseCase.swift
      ComposeDueReviewsUseCase.swift  Finds weeks owed a review, composes them
  Tests/SlateKitTests/             58 tests, all green

Slate/                             ← the iOS shell
  SlateApp.swift                   Composition root: wires adapters into ports
  Infrastructure/
    Persistence/                   SwiftData @Model records + repositories
    Intelligence/                  FoundationModels adapters (the observer)
    Audio/RecordingSession.swift   AVAudioEngine → SpeechAnalyzer streaming
  Presentation/
    JournalStore.swift             @Observable façade over the use cases
    Theme.swift · Components/ · Screens/
```

Dependency rule: `Presentation → Application → Domain`, and
`Infrastructure → Application ports`. The domain never imports SwiftUI,
SwiftData, Speech, or FoundationModels. The iOS app and the test suite are
just two different sets of adapters plugged into the same core.

### Why it's fast and reliable

- The observer runs **after** an entry is saved — the recorder dismisses
  instantly and the timeline updates in place when the reading arrives.
- Audio conversion and level metering happen on the audio thread; only tiny
  floats hop to the main actor for the waveform.
- Model output is never trusted: `Reflection.sanitized` trims, deduplicates,
  caps, and drops sentence-length tags. Empty output stays silent instead of
  rendering blank UI.
- Review composition is idempotent (verified by test) — relaunching on Sunday
  never duplicates a review.
- Every domain rule above is pinned by a unit test, runnable anywhere Swift runs.

## Running the tests

```sh
cd SlateKit
swift test        # macOS or Linux, no Xcode needed
```

Or in Xcode: open the project, select the `SlateKit` scheme, ⌘U.

Current status: **58 tests, 0 failures.**

## Running Slate on your iPhone

### What you need

- A Mac with **Xcode 26** (macOS Tahoe). Free from the Mac App Store.
- An **iPhone that supports Apple Intelligence** — iPhone 15 Pro / Pro Max or
  any iPhone 16/17-class device — running **iOS 26**, with Apple Intelligence
  turned on in Settings › Apple Intelligence & Siri.
  (On other devices Slate still records, transcribes, and stores perfectly;
  the observer and Sunday reviews simply stay silent.)
- An Apple ID. A paid developer account is **not** required — a free account
  can install on your own phone.

### Steps

1. **Clone and open**
   ```sh
   git clone https://github.com/joaovitor2763/slate.git
   cd slate && open Slate.xcodeproj
   ```
2. **Set your signing team** — select the `Slate` target › *Signing &
   Capabilities* › check *Automatically manage signing* and pick your Apple ID
   team. If the bundle ID collides, change `app.slate.Slate` to anything
   unique (e.g. `com.yourname.slate`).
3. **Plug in your iPhone** (or pair over Wi-Fi) and pick it as the run
   destination in the toolbar.
4. **Enable Developer Mode on the phone** if prompted: Settings › Privacy &
   Security › Developer Mode › on, then restart the phone.
5. **Run** (⌘R). On a free Apple ID, the first launch needs one more step:
   Settings › General › VPN & Device Management › trust your developer
   certificate.
6. **First launch on device**: allow microphone access. iOS may download the
   on-device speech model once (a system asset, done by Apple's frameworks —
   Slate itself still makes no network calls). After that, airplane mode
   changes nothing.

### Try the whole loop

1. Tap the mic, speak for a minute, tap ✓. The entry appears instantly.
2. Watch the small pulse: the observer is reading. A moment later the card
   gains its one-line reading and tags.
3. Open the entry — observations first, transcript below. Add context if the
   reading missed your point.
4. Speak on three or more days. On Sunday, the "Your week, read back" card
   appears at the top of the timeline.

## Privacy model, stated precisely

- The **only** data Slate persists is the SwiftData store on your phone
  (transcripts, the observer's notes, reviews). Audio is never written to disk.
- No identifier exists: no account, no device ID collection, no receipt.
- The binary contains no networking code path. The single system-mediated
  download (Apple's speech model assets) is performed by iOS itself.
- Deleting an entry deletes the only copy in existence.
