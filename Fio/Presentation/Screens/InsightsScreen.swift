import SwiftUI
import FioKit

struct InsightsScreen: View {
    @Environment(JournalStore.self) var store
    @Environment(\.locale) var locale
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @AppStorage(AppAppearance.storageKey) var appearance = AppAppearance.system.rawValue
    @AppStorage(InterfaceLanguage.storageKey) var interfaceLanguage = InterfaceLanguage.english.rawValue

    var statistics: UsageStatistics { store.usageStatistics }
    var calendar: JournalCalendar { store.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                identityHeader
                statisticsPanel
                activitySection
                speakingHoursSection
                preferencesSection
                privacyNote
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("insights-screen")
        .background(Theme.background)
        .navigationTitle("Fio")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .task {
            store.prepareUsageStatistics()
        }
    }
}
