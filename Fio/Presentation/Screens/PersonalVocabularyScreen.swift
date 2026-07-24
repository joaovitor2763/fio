import SwiftUI
import FioKit

struct PersonalVocabularyScreen: View {
    @State private var rules: [VocabularyRule] = []
    @State private var editingRule: VocabularyRule?

    var body: some View {
        List {
            Section {
                Label(
                    "Teach Fio names and terms you use. Corrections happen on this iPhone before a reflection is created.",
                    systemImage: "text.badge.checkmark"
                )
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }

            Section {
                if rules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No words yet")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Add a word Fio often hears incorrectly, such as G4S → G4OS.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(rules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            vocabularyRow(rule)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteRules)
                }
            } header: {
                Text("Replacements")
            } footer: {
                if !rules.isEmpty {
                    Text("Swipe a replacement to delete it. New rules affect future transcriptions; existing entries only change when you apply the vocabulary manually.")
                }
            }

            if rules.isEmpty {
                Section {
                    Button {
                        editingRule = VocabularyRule(source: "", replacement: "")
                    } label: {
                        Label("Add word", systemImage: "plus")
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Personal vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingRule = VocabularyRule(source: "", replacement: "")
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(rules.count >= PersonalVocabulary.maximumRuleCount)
                .accessibilityLabel("Add word")
            }
        }
        .sheet(item: $editingRule) { rule in
            VocabularyRuleEditor(
                rule: rule,
                existingRules: rules
            ) { savedRule in
                PersonalVocabulary.upsert(savedRule)
                reloadRules()
            }
        }
        .onAppear(perform: reloadRules)
    }

    private func vocabularyRow(_ rule: VocabularyRule) -> some View {
        HStack(spacing: 10) {
            Text(rule.source)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
            Text(rule.replacement)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .contentShape(Rectangle())
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            PersonalVocabulary.remove(id: rules[index].id)
        }
        reloadRules()
    }

    private func reloadRules() {
        rules = PersonalVocabulary.rules
    }
}

private struct VocabularyRuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    let existingRules: [VocabularyRule]
    let onSave: (VocabularyRule) -> Void

    @State private var draft: VocabularyRule

    init(
        rule: VocabularyRule,
        existingRules: [VocabularyRule],
        onSave: @escaping (VocabularyRule) -> Void
    ) {
        self.existingRules = existingRules
        self.onSave = onSave
        _draft = State(initialValue: rule)
    }

    private var cleanSource: String {
        draft.source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanReplacement: String {
        draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        let normalized = cleanSource.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
        return existingRules.contains {
            $0.id != draft.id
                && $0.source.folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased() == normalized
        }
    }

    private var hasConflict: Bool {
        VocabularyProcessor.conflicts(
            VocabularyRule(
                id: draft.id,
                source: cleanSource,
                replacement: cleanReplacement
            ),
            with: existingRules.filter { $0.id != draft.id }
        )
    }

    private var canSave: Bool {
        VocabularyProcessor.isValid(
            source: cleanSource,
            replacement: cleanReplacement
        ) && !isDuplicate && !hasConflict
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Add the version Fio hears first, then the spelling you want to keep.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)

                    vocabularyField(
                        title: "When Fio writes",
                        placeholder: "G4S",
                        text: $draft.source
                    )

                    vocabularyField(
                        title: "Replace with",
                        placeholder: "G4OS",
                        text: $draft.replacement
                    )

                    if isDuplicate {
                        Label(
                            "A replacement for this word already exists.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    }

                    if hasConflict {
                        Label(
                            "This replacement overlaps with another rule.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    }

                    if !cleanSource.isEmpty || !cleanReplacement.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Preview")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.secondaryText)

                            HStack(spacing: 10) {
                                Text(cleanSource.isEmpty ? "G4S" : cleanSource)
                                    .foregroundStyle(Theme.secondaryText)
                                    .strikethrough(!cleanReplacement.isEmpty)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.tertiaryText)
                                Text(
                                    cleanReplacement.isEmpty
                                        ? "G4OS"
                                        : cleanReplacement
                                )
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.primaryText)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Theme.card)
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Vocabulary replacement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            VocabularyRule(
                                id: draft.id,
                                source: cleanSource,
                                replacement: cleanReplacement
                            )
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private func vocabularyField(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                )
        }
    }
}
