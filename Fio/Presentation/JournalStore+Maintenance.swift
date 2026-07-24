import Foundation
import FioKit

extension JournalStore {
    /// Called on launch and whenever the app comes to the foreground.
    func composeDueReviews() async {
        guard isLoaded,
              isReviewSnapshotReady,
              !isComposingReviews else { return }
        await withReviewMutation {
            guard isLoaded,
                  isReviewSnapshotReady,
                  !isComposingReviews else { return }
            isComposingReviews = true
            defer { isComposingReviews = false }
            do {
                let created = try await composeReviews.execute(
                    entries: entries,
                    existingReviews: reviews
                )
                if !created.isEmpty {
                    reviews = (reviews + created).sorted {
                        $0.weekStart > $1.weekStart
                    }
                }
                hasReviewMaintenanceError = false
            } catch {
                // The use case persists one week at a time. A later failure
                // can follow successful commits, so replace the cache from
                // the authoritative repository before releasing the lock.
                do {
                    let loadedReviews = try await reviewRepository.allReviews()
                    reviews = loadedReviews.sorted {
                        $0.weekStart > $1.weekStart
                    }
                    isReviewSnapshotReady = true
                } catch {
                    isReviewSnapshotReady = false
                }
                hasReviewMaintenanceError = true
            }
            updateMaintenanceErrorMessage()
        }
    }

    /// Topics and reviews enrich the journal but must never make readable
    /// entries unavailable. Failures are shown as a retryable, non-blocking
    /// banner while the successful entry snapshot remains on screen.
    func refreshAuxiliarySnapshots() async {
        do {
            try await PerformanceRecorder.measure(
                "topics_reconcile"
            ) {
                try await withTopicMutation {
                    let entrySnapshot = entries
                    let validEntryIDs = PerformanceRecorder.measureSync(
                        "entry_id_index"
                    ) {
                        Set(entrySnapshot.map(\.id))
                    }
                    if !didMigrateLegacyTags {
                        if LegacyTopicMigrationState.isComplete {
                            didMigrateLegacyTags = true
                        } else {
                            try await migrateLegacyTags.execute(
                                entries: entrySnapshot
                            )
                            LegacyTopicMigrationState.markComplete()
                            didMigrateLegacyTags = true
                        }
                    }
                    let loadedTopics = try await reconcileTopicMemberships.execute(
                        validEntryIDs: validEntryIDs
                    )
                    applyTopics(loadedTopics)
                }
            }
            hasTopicMaintenanceError = false
        } catch {
            hasTopicMaintenanceError = true
            if !didMigrateLegacyTags {
                didMigrateLegacyTags = false
            }
            do {
                try await withTopicMutation {
                    let fallbackTopics = try await topicRepository.allTopics()
                    let validEntryIDs = Set(entries.map(\.id))
                    applyTopics(
                        reconcileTopicMemberships.repairedSnapshot(
                            fallbackTopics,
                            validEntryIDs: validEntryIDs
                        )
                    )
                }
            } catch {
                // Keep the last usable in-memory snapshot and show retry.
            }
        }

        await withReviewMutation {
            do {
                let loadedReviews = try await PerformanceRecorder.measure(
                    "reviews_fetch"
                ) {
                    try await reviewRepository.allReviews()
                }
                reviews = loadedReviews.sorted {
                    $0.weekStart > $1.weekStart
                }
                isReviewSnapshotReady = true
                hasReviewMaintenanceError = false
            } catch {
                isReviewSnapshotReady = false
                hasReviewMaintenanceError = true
            }
        }

        updateMaintenanceErrorMessage()
    }

    func updateMaintenanceErrorMessage() {
        maintenanceErrorMessage = (
            hasTopicMaintenanceError || hasReviewMaintenanceError
        )
            ? String(
                localized: "Your entries are ready, but some journal details could not be updated."
            )
            : nil
    }

    /// Catches up at most once per local day when the journal changed. This is
    /// safe to call on every foreground transition: reopening the app does not
    /// start another model pass after a successful consolidation that day.
    func runDreamIfNeeded() async {
        _ = await runDream(force: false)
    }

    /// Explicitly requested by the observer from Reflection. Manual runs bypass
    /// the daily/dirty gate but remain entirely on-device.
    @discardableResult
    func runDreamNow() async -> Bool {
        await runDream(force: true)
    }

    @discardableResult
    private func runDream(force: Bool) async -> Bool {
        guard !isDreaming else { return false }
        isDreaming = true
        defer { isDreaming = false }

        for attempt in 0..<2 where !Task.isCancelled {
            switch await runDreamPass(force: force) {
            case .completed:
                return true
            case .skippedOrFailed:
                return false
            case .corpusChanged:
                guard attempt == 0 else { return false }
                await Task.yield()
            }
        }
        return false
    }

    private func runDreamPass(force: Bool) async -> DreamPassResult {
        let availableEntries: [Entry]
        if isLoaded {
            availableEntries = entries
        } else {
            availableEntries = (try? await entryRepository.allEntries()) ?? []
        }
        let substantialEntries = availableEntries.filter { $0.transcript.isSubstantial }
        let latestEntryDate = substantialEntries.map(\.createdAt).max() ?? .distantPast
        if !force {
            guard DreamScheduleState.shouldRunAutomatically(
                latestEntryDate: latestEntryDate,
                now: .now
            ) else {
                return .skippedOrFailed
            }
        }
        let corpusRevision = DreamScheduleState.currentRevision

        if substantialEntries.count < 2 {
            do {
                return try await withTopicMutation {
                    let persistedTopics = try await saveDreamSuggestions.execute(
                        candidates: []
                    )
                    guard DreamScheduleState.markAnalyzed(
                        through: latestEntryDate,
                        ifRevisionIs: corpusRevision,
                        completedAt: .now
                    ) else {
                        return .corpusChanged
                    }
                    applyTopics(persistedTopics)
                    return .completed
                }
            } catch {
                // Leave the revision stale so a later pass retries cleanup.
                return .skippedOrFailed
            }
        }

        let allTopics = isLoaded
            ? topics
            : ((try? await topicRepository.allTopics()) ?? [])
        guard let candidates = await topicDiscoveryService.discoverTopics(
            in: substantialEntries,
            existingTopics: allTopics
        ) else {
            return .skippedOrFailed
        }
        guard DreamScheduleState.currentRevision == corpusRevision else {
            return .corpusChanged
        }

        do {
            return try await withTopicMutation {
                let persistedTopics = try await saveDreamSuggestions.execute(
                    candidates: candidates
                )
                guard DreamScheduleState.markAnalyzed(
                    through: latestEntryDate,
                    ifRevisionIs: corpusRevision,
                    completedAt: .now
                ) else {
                    return .corpusChanged
                }
                applyTopics(persistedTopics)
                return .completed
            }
        } catch {
            // Leave the Dream stale so a later foreground or background pass retries.
            return .skippedOrFailed
        }
    }

}

private enum DreamPassResult {
    case completed
    case skippedOrFailed
    case corpusChanged
}
