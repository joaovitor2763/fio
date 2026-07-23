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
  extend 30 seconds at a time.
- **Timeline** — your days, newest first, with the observer's one-line
  reading of each entry and its topic tags.
- **Entry** — the observations, the tags, the full transcript. If the
  reading is off, add context in your own words; the observer reads that too.
- **Review** — on Sunday, Slate reads the week back to you: a title, a
  sparkline of how much you spoke each day, and one or two plain paragraphs
  about what happened.

## Building

- Xcode 26, iOS 26 SDK.
- Runs on an iPhone with Apple Intelligence enabled. Without it the app
  still records, transcribes, and stores — the observer simply stays silent.
- Open `Slate.xcodeproj`, set your signing team, build the `Slate` scheme.

## Project layout

```
Slate/
  SlateApp.swift              App entry, SwiftData container
  Models/                     JournalEntry, WeeklyReview (@Model)
  Audio/RecordingSession.swift  AVAudioEngine → SpeechAnalyzer streaming
  Intelligence/Reflector.swift  Per-entry reflection (FoundationModels)
  Intelligence/WeekComposer.swift  The Sunday read-back
  Views/                      Timeline, Record, Entry, Review screens
  Support/Theme.swift         Colors, formatters, tag layout
```
