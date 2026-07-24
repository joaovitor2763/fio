import SwiftUI

struct ActivityWeek: Identifiable {
    let start: Date
    let days: [Date]
    var id: Date { start }
}

struct ObserverGuidanceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ObserverPreferences.guidanceStorageKey) private var storedGuidance = ""
    @State private var draftGuidance = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add an optional preference for future reflections.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)

            TextEditor(text: $draftGuidance)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 180)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                .onChange(of: draftGuidance) { _, newValue in
                    if newValue.count > ObserverPreferences.maximumGuidanceLength {
                        draftGuidance = String(
                            newValue.prefix(ObserverPreferences.maximumGuidanceLength)
                        )
                    }
                }

            Text("\(draftGuidance.count)/\(ObserverPreferences.maximumGuidanceLength)")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("For example: “Focus on decisions and recurring themes. Use direct language.” Fio still stays factual and never gives advice or invents details.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            Spacer()
        }
        .padding(20)
        .background(Theme.background)
        .navigationTitle("Observer guidance")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    storedGuidance = ObserverPreferences.normalizedGuidance(draftGuidance)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            draftGuidance = storedGuidance
        }
    }
}

struct LanguageSelectionScreen: View {
    @Environment(\.locale) private var locale
    @AppStorage(TranscriptionLanguagePreference.storageKey)
    private var selection = TranscriptionLanguagePreference.defaultSelection
    @State private var availableLocales: [Locale] = []

    var body: some View {
        List {
            Section {
                languageRow(
                    title: appLocalized("Automatic (iPhone)", locale: locale),
                    subtitle: appLocalized("Uses the first supported preferred language", locale: locale),
                    identifier: TranscriptionLanguagePreference.automaticSelection
                )
            } footer: {
                Text("Apple's speech transcriber needs a language before recording starts. Automatic follows your iPhone preferences; it does not detect the language from the audio.")
            }

            Section("Languages on this iPhone") {
                if availableLocales.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading languages…")
                    }
                    .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(
                        availableLocales,
                        id: \.self
                    ) { locale in
                        let identifier = TranscriptionLanguagePreference.identifier(for: locale)
                        languageRow(
                            title: TranscriptionLanguagePreference.displayName(for: locale),
                            subtitle: identifier,
                            identifier: identifier
                        )
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .task {
            availableLocales = await TranscriptionLanguagePreference.availableLocales()
        }
    }

    private func languageRow(
        title: String,
        subtitle: String,
        identifier: String
    ) -> some View {
        Button {
            selection = identifier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if selection == identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
