# Performance

Fio includes an opt-in Debug benchmark so performance work can be compared
against the same local journal without adding telemetry to release builds.

## Current baseline

Measured on July 24, 2026 with Xcode 26, an iPhone 17 Pro simulator, a warm
launch, and a deterministic journal containing 2,000 entries and 100 topics.
Percentiles use 20 independent launches.

| Metric | Before p50 / p90 / p99 | Current p50 / p90 / p99 | p90 change |
| --- | ---: | ---: | ---: |
| Journal refresh | 448.9 / 459.4 / 461.8 ms | 194.7 / 209.3 / 299.8 ms | -54.4% |
| First content ready | 1,096.1 / 1,106.6 / 1,108.8 ms | 865.6 / 884.5 / 1,202.0 ms | -20.1% |

The operation fixture also measured:

- Insights statistics read: 0.001 / 0.002 / 0.009 ms p50/p90/p99. The
  approximately 390 ms aggregate calculation runs once on a utility task.
- Search across the 2,000-entry in-memory index: 14.6 / 25.0 / 27.5 ms.
- Save-context including persistence and snapshot update: 27.7 / 48.8 /
  88.9 ms. This path no longer performs a full journal refresh.

Debug timings are intentionally local diagnostics, not production analytics.

## Reproducing the fixture

Launch the Debug app with:

- `FIO_PERFORMANCE_LOG=1` to emit `FIO_PERF` signposts through unified logging.
- `FIO_PERFORMANCE_FIXTURE_ENTRIES=2000` on a clean app container to seed the
  deterministic journal.
- `FIO_PERFORMANCE_OPERATIONS=1` to exercise search, statistics reads, and
  context saves after first content becomes visible.

The fixture never runs unless these environment variables are explicitly set,
and all fixture code is excluded from non-Debug builds.

## Regression checks

The domain suite and critical UI journeys can be reproduced with:

```sh
swift test --package-path FioKit
xcodebuild test \
  -project Fio.xcodeproj \
  -scheme Fio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FioUITests
```

The UI suite seeds and resets its own deterministic Debug fixture. It covers
search-to-detail navigation, writing/saving/deleting an entry, Insights,
Reviews, and the recorder presentation. Microphone and speech-model access are
stubbed only for this Debug UI-test launch; normal Debug and all Release
launches use the real on-device recording pipeline.
