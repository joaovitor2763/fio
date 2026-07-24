import SwiftUI
import FioKit

extension InsightsScreen {
    var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Preferences")

            VStack(spacing: 0) {
                preferencePickerRow(
                    title: "Appearance",
                    systemName: "circle.lefthalf.filled",
                    selection: $appearance,
                    options: AppAppearance.allCases.map { ($0.rawValue, $0.title) }
                )

                Divider()
                    .overlay(Theme.cardStroke)
                    .padding(.leading, 52)

                preferencePickerRow(
                    title: "Interface language",
                    systemName: "character.bubble",
                    selection: $interfaceLanguage,
                    options: InterfaceLanguage.allCases.map { ($0.rawValue, $0.title) }
                )
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))

            NavigationLink {
                LanguageSelectionScreen()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Transcription language")
                            .foregroundStyle(Theme.primaryText)
                        Text(TranscriptionLanguagePreference.selectedDisplayName)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            }
            .buttonStyle(.plain)

            NavigationLink {
                PersonalVocabularyScreen()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.badge.checkmark")
                        .frame(width: 24)
                        .foregroundStyle(Theme.secondaryText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Personal vocabulary")
                            .foregroundStyle(Theme.primaryText)
                        Text("Teach Fio names and words you use")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            }
            .buttonStyle(.plain)

            NavigationLink {
                ObserverGuidanceScreen()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .frame(width: 24)
                        .foregroundStyle(Theme.secondaryText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Observer guidance")
                            .foregroundStyle(Theme.primaryText)
                        Text("Choose what reflections should emphasize")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            }
            .buttonStyle(.plain)
        }
    }

    func preferencePickerRow(
        title: LocalizedStringKey,
        systemName: String,
        selection: Binding<String>,
        options: [(value: String, title: LocalizedStringKey)]
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .frame(width: 24)
                .foregroundStyle(Theme.secondaryText)

            Text(title)
                .foregroundStyle(Theme.primaryText)

            Spacer()

            Picker(title, selection: selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Theme.secondaryText)
        }
        .padding(16)
    }

}
