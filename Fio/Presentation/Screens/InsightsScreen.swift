import SwiftUI
import FioKit

struct InsightsScreen: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.locale) private var locale
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(InterfaceLanguage.storageKey) private var interfaceLanguage = InterfaceLanguage.english.rawValue

    private var statistics: UsageStatistics { store.usageStatistics }
    private var calendar: JournalCalendar { store.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                identityCard
                metricGrid
                activitySection
                speakingHoursSection
                preferencesSection
                privacyNote
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("Fio")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.title2.weight(.medium))
                .foregroundStyle(Theme.primaryControlForeground)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Theme.primaryControlBackground))

            VStack(alignment: .leading, spacing: 3) {
                Text("Your private voice journal")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("No account · only this iPhone")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            metricCard(
                value: statistics.totalWords.formatted(.number.notation(.compactName)),
                label: "Words spoken"
            )
            metricCard(
                value: usageDuration(statistics.totalDuration),
                label: "Time recorded"
            )
            metricCard(
                value: "\(statistics.currentStreak)",
                label: "Current streak"
            )
            metricCard(
                value: "\(statistics.longestStreak)",
                label: "Longest streak"
            )
            metricCard(
                value: "\(statistics.activeDayCount)",
                label: "Active days"
            )
            metricCard(
                value: "\(statistics.recordingCount)",
                label: "Recordings"
            )
        }
    }

    private func metricCard(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Activity", detail: appLocalized("Last 52 weeks", locale: locale))

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(activityWeeks) { week in
                        VStack(spacing: 4) {
                            ForEach(week.days, id: \.self) { day in
                                activityCell(for: day)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)

            HStack(spacing: 5) {
                Text("Less")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(activityColor(level: level))
                        .frame(width: 12, height: 12)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var speakingHoursSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                "When you speak",
                detail: statistics.peakHour.map(hourRange)
                    ?? appLocalized("Not enough data yet", locale: locale)
            )

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            statistics.hourlyRecordingCounts[hour] > 0
                                ? Theme.primaryText
                                : Theme.card
                        )
                        .frame(
                            height: hourBarHeight(
                                count: statistics.hourlyRecordingCounts[hour]
                            )
                        )
                        .accessibilityLabel(
                            "\(hourRange(hour)): \(statistics.hourlyRecordingCounts[hour]) recordings"
                        )
                }
            }
            .frame(height: 84, alignment: .bottom)

            HStack {
                Text("12 AM")
                Spacer()
                Text("6 AM")
                Spacer()
                Text("12 PM")
                Spacer()
                Text("6 PM")
            }
            .font(.caption2)
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var preferencesSection: some View {
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
        }
    }

    private func preferencePickerRow(
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

    private var privacyNote: some View {
        Label(
            "These insights are calculated on this iPhone from your journal. Nothing is uploaded.",
            systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(Theme.tertiaryText)
    }

    private func sectionHeader(_ title: LocalizedStringKey, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func activityCell(for day: Date) -> some View {
        let today = calendar.startOfDay(.now)
        let duration = statistics.durationByDay[calendar.startOfDay(day), default: 0]
        let level = activityLevel(duration: duration)

        return RoundedRectangle(cornerRadius: 3)
            .fill(day > today ? Color.clear : activityColor(level: level))
            .frame(width: 12, height: 12)
            .accessibilityLabel(
                "\(day.formatted(date: .abbreviated, time: .omitted)): \(usageDuration(duration))"
            )
    }

    private func activityLevel(duration: TimeInterval) -> Int {
        switch duration {
        case ...0: 0
        case ...120: 1
        case ...300: 2
        case ...900: 3
        default: 4
        }
    }

    private func activityColor(level: Int) -> Color {
        switch level {
        case 1: Theme.primaryText.opacity(0.18)
        case 2: Theme.primaryText.opacity(0.38)
        case 3: Theme.primaryText.opacity(0.65)
        case 4: Theme.primaryText
        default: Theme.card
        }
    }

    private var activityWeeks: [ActivityWeek] {
        let currentWeek = calendar.weekStart(containing: .now)
        return (0..<52).compactMap { offset in
            guard let start = calendar.calendar.date(
                byAdding: .weekOfYear,
                value: offset - 51,
                to: currentWeek
            ) else { return nil }
            let days = (0..<7).compactMap {
                calendar.calendar.date(byAdding: .day, value: $0, to: start)
            }
            return ActivityWeek(start: start, days: days)
        }
    }

    private func hourBarHeight(count: Int) -> CGFloat {
        let maximum = max(statistics.hourlyRecordingCounts.max() ?? 0, 1)
        return 5 + (CGFloat(count) / CGFloat(maximum)) * 72
    }

    private func hourRange(_ hour: Int) -> String {
        var startComponents = DateComponents()
        startComponents.hour = hour
        var endComponents = DateComponents()
        endComponents.hour = (hour + 1) % 24
        let start = calendar.calendar.date(from: startComponents) ?? .now
        let end = calendar.calendar.date(from: endComponents) ?? .now
        return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private func usageDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

private struct ActivityWeek: Identifiable {
    let start: Date
    let days: [Date]
    var id: Date { start }
}

private struct LanguageSelectionScreen: View {
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
