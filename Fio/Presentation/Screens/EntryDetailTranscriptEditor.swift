import SwiftUI
import FioKit

extension EntryDetailScreen {
    func transcriptEditor(for entry: Entry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Correct the words below. Your reflection will stay as it is.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                TextEditor(text: $draftTranscript)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))

                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Edit transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTranscriptEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let currentRules = PersonalVocabulary.rules
                        let suggestion = currentRules.count
                            < PersonalVocabulary.maximumRuleCount
                            ? VocabularyProcessor.suggestion(
                                from: entry.transcript.text,
                                to: draftTranscript,
                                existingRules: currentRules
                            )
                            : nil
                        let shouldSuggestReflectionRefresh =
                            !entry.reflection.isSilent
                            && Transcript(draftTranscript) != entry.transcript
                        Task {
                            do {
                                try await store.saveTranscript(
                                    draftTranscript,
                                    forEntryID: entry.id
                                )
                                showTranscriptEditor = false
                                vocabularySuggestion = suggestion
                                showReflectionRefreshSuggestion =
                                    shouldSuggestReflectionRefresh
                            } catch {
                                transcriptEditorError = error.localizedDescription
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        draftTranscript.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .alert(
            "Entry could not be updated",
            isPresented: Binding(
                get: { transcriptEditorError != nil },
                set: { if !$0 { transcriptEditorError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriptEditorError ?? "")
        }
    }

    func applyVocabulary(
        _ application: VocabularyApplication,
        to entry: Entry
    ) {
        let shouldSuggestReflectionRefresh =
            !entry.reflection.isSilent
            && Transcript(application.text) != entry.transcript
        Task {
            do {
                try await store.saveTranscript(
                    application.text,
                    forEntryID: entry.id
                )
                showReflectionRefreshSuggestion =
                    shouldSuggestReflectionRefresh
            } catch {
                updateError = error.localizedDescription
            }
        }
    }

    func contextEditor(for entry: Entry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Say what you actually meant. The observer reads this too.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                TextEditor(text: $draftContext)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Add context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showContextEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.saveContext(draftContext, forEntryID: entry.id)
                            showContextEditor = false
                        }
                    }
                }
            }
        }
    }
}
