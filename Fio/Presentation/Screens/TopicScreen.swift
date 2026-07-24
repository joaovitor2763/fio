import SwiftUI
import FioKit

struct TopicScreen: View {
    let topicID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    @Environment(\.locale) private var locale
    @State private var draftName = ""
    @State private var showRename = false
    @State private var showActionError = false

    private var topic: Topic? { store.topic(withID: topicID) }
    private var entries: [Entry] { store.entries(forTopicID: topicID) }
    private var title: Text {
        if topic?.status == .suggested {
            Text("Recurring topic")
        } else {
            Text(verbatim: topic?.name ?? "")
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let topic {
                    if topic.status == .suggested {
                        suggestionReview(topic)
                    } else {
                        acceptedHeader(topic)
                    }

                    if entries.isEmpty {
                        Text("No connected entries.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 20)
                    } else {
                        Text(topic.status == .suggested ? "Why Fio noticed this" : "Connected entries")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 6)

                        ForEach(entries) { entry in
                            NavigationLink(value: Route.entry(entry.id)) {
                                topicEntryCard(entry)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .toolbar {
            if topic?.status == .accepted {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftName = topic?.name ?? ""
                        showRename = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Rename topic")
                }
            }
        }
        .alert("Rename topic", isPresented: $showRename) {
            TextField("Topic name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                Task {
                    let accepted = await store.acceptTopicSuggestion(
                        topicID,
                        renamedTo: draftName
                    )
                    if let accepted, accepted.id != topicID {
                        dismiss()
                    } else if accepted == nil {
                        showActionError = true
                    }
                }
            }
            .disabled(Topic.sanitizedName(draftName) == nil)
        } message: {
            Text("The new name appears on every connected entry.")
        }
        .alert("Topic could not be updated", isPresented: $showActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your topic is unchanged. Please try again.")
        }
        .task(id: topic?.name) {
            if draftName.isEmpty {
                draftName = topic?.name ?? ""
            }
        }
        .onChange(of: topic?.id) { previousID, currentID in
            if previousID != nil, currentID == nil {
                dismiss()
            }
        }
    }

    private func suggestionReview(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text("A thread is forming")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
            }

            Text("Fio found the same contextual idea in \(topic.entryIDs.count) different entries.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)

            TextField("Topic name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Theme.background)
                )

            HStack(spacing: 10) {
                Button {
                    Task {
                        let accepted = await store.acceptTopicSuggestion(
                            topic.id,
                            renamedTo: draftName
                        )
                        if let accepted, accepted.id != topic.id {
                            dismiss()
                        } else if accepted == nil {
                            showActionError = true
                        }
                    }
                } label: {
                    Text("Keep topic")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primaryControlForeground)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.primaryControlBackground)
                )
                .disabled(
                    Topic.sanitizedName(draftName) == nil
                )

                Button("Ignore", role: .destructive) {
                    Task {
                        if await store.dismissTopicSuggestion(topic.id) {
                            dismiss()
                        } else {
                            showActionError = true
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 8)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }

    private func acceptedHeader(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(topic.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            if topic.entryIDs.count == 1 {
                Text("1 connected entry")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(topic.entryIDs.count) connected entries")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func topicEntryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                entry.createdAt.formatted(
                    .dateTime
                        .month(.abbreviated)
                        .day()
                        .year()
                        .locale(locale)
                )
            )
            .font(.caption)
            .foregroundStyle(Theme.tertiaryText)

            Text(entry.timelineLine)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)

            Text(entry.transcript.excerpt(maxCharacters: 180))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }
}
