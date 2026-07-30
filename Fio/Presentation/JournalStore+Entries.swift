import Foundation
import FioKit

extension JournalStore {
    // MARK: - Writing

    /// Stores the entry immediately so the timeline updates at once, then
    /// lets the observer read it in the background.
    func finishRecording(
        transcriptText: String,
        duration: TimeInterval,
        audioFileName: String?,
        replacing replacedID: UUID? = nil,
        applyPersonalVocabulary: Bool = false,
        at date: Date = .now
    ) async {
        let replacedEntry = replacedID.flatMap { entry(withID: $0) }
        let replacedAudioFileName = replacedEntry?.audioFileName
        let entryDate = replacedEntry?.createdAt ?? min(date, .now)
        let textToSave = applyPersonalVocabulary
            ? PersonalVocabulary.apply(to: transcriptText).text
            : transcriptText

        let savedEntry: Entry
        var didRefreshReplacementTopics = false
        do {
            let saved: Entry?
            if replacedID != nil {
                let replacement = try await withTopicMutation {
                    let entry = try await recordEntry.execute(
                        transcriptText: textToSave,
                        duration: duration,
                        audioFileName: audioFileName,
                        replacing: replacedID,
                        at: entryDate
                    )
                    if let entry, let replacedID {
                        upsertEntry(entry, removing: replacedID)
                    }
                    guard let entry, let replacedID else {
                        return (entry, false)
                    }
                    if let persistedTopics = try? await topicRepository.allTopics() {
                        applyTopics(persistedTopics)
                        return (entry, true)
                    }
                    replaceTopicEntryReferenceInSnapshot(
                        from: replacedID,
                        to: entry.id
                    )
                    return (entry, false)
                }
                saved = replacement.0
                didRefreshReplacementTopics = replacement.1
            } else {
                saved = try await recordEntry.execute(
                    transcriptText: textToSave,
                    duration: duration,
                    audioFileName: audioFileName,
                    at: entryDate
                )
            }
            guard let saved else {
                AudioFileStore.deleteFile(named: audioFileName)
                return
            }
            savedEntry = saved
        } catch {
            AudioFileStore.deleteFile(named: audioFileName)
            return
        }

        if replacedID != nil {
            hasTopicMaintenanceError = !didRefreshReplacementTopics
            updateMaintenanceErrorMessage()
        }
        if replacedAudioFileName != audioFileName {
            AudioFileStore.deleteFile(named: replacedAudioFileName)
        }
        DreamScheduleState.markNeedsAnalysis()
        if replacedID == nil {
            upsertEntry(savedEntry)
        }

#if DEBUG
        guard ProcessInfo.processInfo.environment["FIO_UI_TESTING"] != "1" else {
            return
        }
#endif
        Task {
            await regenerateReflection(entryID: savedEntry.id)
        }
    }

    func delete(entryID: UUID) async {
        let audioFileName = entry(withID: entryID)?.audioFileName
        do {
            try await deleteEntry.execute(entryID: entryID)
        } catch {
            return
        }

        // Entry deletion is committed. Keep the readable snapshot consistent
        // even when topic persistence needs a later retry.
        removeEntryFromSnapshot(entryID)
        let didCleanUpTopics = await withTopicMutation {
            do {
                let persistedTopics = try await removeEntryFromTopics.execute(
                    entryID: entryID
                )
                applyTopics(persistedTopics)
                return true
            } catch {
                applyTopics(
                    reconcileTopicMemberships.repairedSnapshot(
                        topics,
                        validEntryIDs: Set(entries.map(\.id))
                    )
                )
                return false
            }
        }
        hasTopicMaintenanceError = !didCleanUpTopics
        updateMaintenanceErrorMessage()
        AudioFileStore.deleteFile(named: audioFileName)
        DreamScheduleState.markNeedsAnalysis()
    }

    func saveContext(_ text: String, forEntryID id: UUID) async {
        await PerformanceRecorder.measure("save_context") {
            guard let updated = try? await amendContext.execute(
                entryID: id,
                context: text
            ) else {
                return
            }
            DreamScheduleState.markNeedsAnalysis()
            upsertEntry(updated)
        }
    }

    func saveTranscript(_ text: String, forEntryID id: UUID) async throws {
        guard let updated = try await replaceTranscript.execute(
            entryID: id,
            transcriptText: text
        ) else {
            throw JournalStoreError.transcriptionUnavailable
        }
        DreamScheduleState.markNeedsAnalysis()
        upsertEntry(updated)
    }

    func saveReflection(
        headline: String,
        observations: [String],
        forEntryID id: UUID
    ) async throws {
        guard let updated = try await replaceReflection.execute(
            entryID: id,
            headline: headline,
            observations: observations
        ) else {
            throw JournalStoreError.entryUnavailable
        }
        DreamScheduleState.markNeedsAnalysis()
        upsertEntry(updated)
    }

    func saveTopics(_ names: [String], forEntryID id: UUID) async throws {
        DreamScheduleState.markNeedsAnalysis()
        let didSave = try await withTopicMutation {
            guard let persistedTopics = try await replaceEntryTopics.execute(
                entryID: id,
                names: names
            ) else {
                return false
            }
            applyTopics(persistedTopics)
            return true
        }
        guard didSave else {
            throw JournalStoreError.entryUnavailable
        }
        hasTopicMaintenanceError = false
        updateMaintenanceErrorMessage()
    }

    @discardableResult
    func acceptTopicSuggestion(
        _ topicID: UUID,
        renamedTo name: String? = nil
    ) async -> Topic? {
        DreamScheduleState.markNeedsAnalysis()
        do {
            let acceptedTopic: Topic? = try await withTopicMutation {
                guard let result = try await resolveTopicSuggestion.accept(
                    topicID: topicID,
                    renamedTo: name
                ) else {
                    return nil
                }
                applyTopics(result.topics)
                return result.acceptedTopic
            }
            guard let acceptedTopic else {
                return nil
            }
            hasTopicMaintenanceError = false
            updateMaintenanceErrorMessage()
            return acceptedTopic
        } catch {
            return nil
        }
    }

    @discardableResult
    func dismissTopicSuggestion(_ topicID: UUID) async -> Bool {
        DreamScheduleState.markNeedsAnalysis()
        do {
            try await withTopicMutation {
                let persistedTopics = try await resolveTopicSuggestion.dismiss(
                    topicID: topicID
                )
                applyTopics(persistedTopics)
            }
            hasTopicMaintenanceError = false
            updateMaintenanceErrorMessage()
            return true
        } catch {
            return false
        }
    }

    func regenerateReflection(
        entryID: UUID,
        style: ReflectionStyle = .standard
    ) async {
        guard !annotatingEntryIDs.contains(entryID) else {
            pendingReflectionStyles[entryID] = style
            return
        }

        annotatingEntryIDs.insert(entryID)
        var nextStyle: ReflectionStyle? = style
        while let currentStyle = nextStyle {
            let updated = try? await annotateEntry.execute(
                entryID: entryID,
                style: currentStyle,
                guidance: ObserverPreferences.guidance
            )
            DreamScheduleState.markNeedsAnalysis()
            if let updated {
                upsertEntry(updated)
            }
            nextStyle = pendingReflectionStyles.removeValue(forKey: entryID)
        }
        annotatingEntryIDs.remove(entryID)
    }

    /// Reprocesses the preserved audio with a different language without
    /// changing the language preference used for future recordings.
    func retranscribe(entryID: UUID, locale: Locale) async throws {
        guard let fileName = entry(withID: entryID)?.audioFileName else {
            throw JournalStoreError.audioUnavailable
        }

        let transcript = try await AudioRetranscriptionService.transcribe(
            fileName: fileName,
            locale: locale
        )
        let correctedTranscript = PersonalVocabulary.apply(to: transcript).text
        guard let updated = try await replaceTranscript.execute(
            entryID: entryID,
            transcriptText: correctedTranscript
        ) else {
            throw JournalStoreError.transcriptionUnavailable
        }
        DreamScheduleState.markNeedsAnalysis()
        upsertEntry(updated)

        Task {
            await regenerateReflection(entryID: updated.id)
        }
    }

}
