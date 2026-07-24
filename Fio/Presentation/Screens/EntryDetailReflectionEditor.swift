import SwiftUI
import FioKit

extension EntryDetailScreen {
    func reflectionEditor(for entry: Entry) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Each item below appears as a bullet in the reflection.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)

                    VStack(spacing: 0) {
                        reflectionBulletField(
                            placeholder: "Main observation",
                            text: $draftHeadline
                        )

                        ForEach($draftObservations) { $observation in
                            Divider()
                                .overlay(Theme.cardStroke)
                                .padding(.leading, 36)

                            HStack(alignment: .top, spacing: 10) {
                                Text("•")
                                    .foregroundStyle(Theme.secondaryText)
                                    .padding(.top, 13)
                                TextField(
                                    "Further observation",
                                    text: $observation.text,
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .padding(.vertical, 12)

                                Button {
                                    draftObservations.removeAll {
                                        $0.id == observation.id
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.tertiaryText)
                                        .padding(.top, 13)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove observation")
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18).fill(Theme.card)
                    )

                    if draftObservations.count < 3 {
                        Button {
                            draftObservations.append(
                                ReflectionObservationDraft(text: "")
                            )
                        } label: {
                            Label("Add observation", systemImage: "plus")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }

                    Text("The first bullet is the main observation. You can add up to three more.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)

                    topicEditor
                        .padding(.top, 12)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showReflectionEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let observations = draftObservations
                            .flatMap {
                                $0.text.split(whereSeparator: \.isNewline)
                            }
                            .map {
                                String($0).trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }
                            .filter { !$0.isEmpty }
                            .prefix(3)
                        Task {
                            do {
                                try await store.saveReflection(
                                    headline: draftHeadline,
                                    observations: Array(observations),
                                    forEntryID: entry.id
                                )
                                try await store.saveTopics(
                                    draftTopicNames,
                                    forEntryID: entry.id
                                )
                                showReflectionEditor = false
                            } catch {
                                reflectionEditorError = error.localizedDescription
                            }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert(
            "Entry could not be updated",
            isPresented: Binding(
                get: { reflectionEditorError != nil },
                set: { if !$0 { reflectionEditorError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reflectionEditorError ?? "")
        }
    }

    var topicEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Topics")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)

            Text("Topics stay attached even when the reflection changes.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)

            if !draftTopicNames.isEmpty {
                WrapLayout {
                    ForEach(draftTopicNames, id: \.self) { name in
                        Button {
                            draftTopicNames.removeAll {
                                Topic.normalizedName($0) == Topic.normalizedName(name)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                TopicPill(name: name)
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove topic \(name)")
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Add a topic", text: $draftTopicInput)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(addDraftTopic)
                Button(action: addDraftTopic) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.primaryText)
                }
                .buttonStyle(.plain)
                .disabled(Topic.sanitizedName(draftTopicInput) == nil)
                .accessibilityLabel("Add topic")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))

            let matches = matchingExistingTopics
            if !matches.isEmpty {
                Text("Existing topics")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                WrapLayout {
                    ForEach(matches) { topic in
                        Button {
                            addDraftTopic(topic.name)
                        } label: {
                            TopicPill(name: topic.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var matchingExistingTopics: [Topic] {
        let selected = Set(draftTopicNames.map(Topic.normalizedName))
        let query = Topic.normalizedName(draftTopicInput)
        return store.acceptedTopics.filter { topic in
            !selected.contains(topic.normalizedName)
                && (query.isEmpty || topic.normalizedName.contains(query))
        }
        .prefix(8)
        .map { $0 }
    }

    func addDraftTopic() {
        addDraftTopic(draftTopicInput)
    }

    func addDraftTopic(_ rawName: String) {
        guard let name = Topic.sanitizedName(rawName) else { return }
        let key = Topic.normalizedName(name)
        guard !draftTopicNames.contains(where: {
            Topic.normalizedName($0) == key
        }) else {
            draftTopicInput = ""
            return
        }
        draftTopicNames.append(name)
        draftTopicInput = ""
    }

    func reflectionBulletField(
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 13)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
    }

}
