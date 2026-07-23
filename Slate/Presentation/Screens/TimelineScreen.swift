import SwiftUI
import SlateKit

/// The journal: a large date, the week strip, and every entry in reverse order.
struct TimelineScreen: View {
    @Environment(JournalStore.self) private var store
    @State private var selectedDay = JournalCalendar().startOfDay(.now)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header

                    if let latest = store.latestReview {
                        NavigationLink(value: Route.review(latest.id)) {
                            ReviewTeaserCard(review: latest)
                        }
                        .buttonStyle(CardButtonStyle())
                    }

                    if store.isLoaded && store.timeline.isEmpty {
                        emptyState
                    }

                    ForEach(store.timeline) { day in
                        daySection(day)
                            .id(day.day)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 90)
            }
            .onChange(of: selectedDay) { _, day in
                if store.timeline.contains(where: { store.calendar.isSameDay($0.day, day) }) {
                    withAnimation(.spring(duration: 0.35)) {
                        proxy.scrollTo(store.calendar.startOfDay(day), anchor: .top)
                    }
                }
            }
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.reviewList) {
                    Image(systemName: "text.book.closed")
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Weekly reviews")
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(selectedDay.formatted(.dateTime.month(.wide).day().year()))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: selectedDay)
                .padding(.top, 8)

            WeekStrip(
                selectedDay: $selectedDay,
                daysWithEntries: store.daysWithEntries,
                calendar: store.calendar
            )
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func daySection(_ day: TimelineDay) -> some View {
        if !store.calendar.isSameDay(day.day, selectedDay) {
            Text(day.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.footnote)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 10)
        }
        ForEach(day.entries) { entry in
            NavigationLink(value: Route.entry(entry.id)) {
                EntryCard(entry: entry, isBeingRead: store.annotatingEntryIDs.contains(entry.id))
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing here yet.")
                .foregroundStyle(Theme.primaryText)
            Text("Tap the microphone and say what's on your mind. Slate writes it down; nothing leaves this phone.")
                .foregroundStyle(Theme.secondaryText)
                .font(.subheadline)
        }
        .padding(.top, 40)
    }
}
