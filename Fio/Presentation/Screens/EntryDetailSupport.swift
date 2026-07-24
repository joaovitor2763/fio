import SwiftUI
import UIKit

struct ExportPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ReflectionObservationDraft: Identifiable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct RetranscriptionLanguagePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var availableLocales: [Locale] = []

    let onSelect: (Locale) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if availableLocales.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading languages…")
                        }
                        .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(availableLocales, id: \.self) { locale in
                            Button {
                                onSelect(locale)
                            } label: {
                                HStack {
                                    Text(TranscriptionLanguagePreference.displayName(for: locale))
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Text(TranscriptionLanguagePreference.identifier(for: locale))
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Choose the language spoken in this audio")
                } footer: {
                    Text("Only this entry is changed. Your language for new recordings stays the same.")
                }
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Transcribe again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                availableLocales = await TranscriptionLanguagePreference.availableLocales()
            }
        }
    }
}

struct AudioScrubber: View {
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.card)
                    .frame(height: 3)

                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: width * CGFloat(progress), height: 3)

                Circle()
                    .fill(Theme.primaryText)
                    .frame(width: 8, height: 8)
                    .offset(x: max(0, width * CGFloat(progress) - 4))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(Double(min(max(value.location.x / width, 0), 1)))
                    }
            )
        }
        .frame(height: 20)
        .accessibilityLabel("Audio position")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
