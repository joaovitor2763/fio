import SwiftUI
import FioKit

/// The journal: a large date, the week strip, and every entry in reverse order.
struct TimelineScreen: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let navigationNamespace: Namespace.ID
    @State private var selectedDay = JournalCalendar().startOfDay(.now)
    @State private var datePickerSelection = JournalCalendar().startOfDay(.now)
    @State private var showDatePicker = false
    @State private var isHeaderOverContent = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.calendar.isSameDay(selectedDay, .now),
                   let latest = store.latestReview {
                    let route = Route.review(latest.id, source: .timeline)
                    NavigationLink(value: route) {
                        ReviewTeaserCard(review: latest)
                            .matchedTransitionSource(id: route, in: navigationNamespace) { source in
                                source
                                    .background(Theme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                            }
                    }
                    .buttonStyle(CardButtonStyle())
                }

                if store.isLoaded {
                    selectedDayContent
                        .id(selectedDay)
                        .transition(dayContentTransition)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 90)
            .animation(reduceMotion ? Motion.quick : Motion.standard, value: selectedDay)
            .animation(Motion.standard, value: store.isLoaded)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 4
        } action: { _, isScrolled in
            withAnimation(.easeInOut(duration: 0.22)) {
                isHeaderOverContent = isScrolled
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .background {
                    if isHeaderOverContent {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                            LinearGradient(
                                colors: [
                                    Theme.background.opacity(0.14),
                                    Theme.background.opacity(0.50),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .ignoresSafeArea(edges: .top)
                    } else {
                        Theme.background
                            .ignoresSafeArea(edges: .top)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isHeaderOverContent {
                        Rectangle()
                            .fill(Theme.primaryText.opacity(0.07))
                            .frame(height: 0.5)
                    }
                }
                .shadow(
                    color: Theme.shadow.opacity(isHeaderOverContent ? 0.24 : 0),
                    radius: isHeaderOverContent ? 14 : 0,
                    y: isHeaderOverContent ? 8 : 0
                )
        }
        .background(Theme.background)
        .sheet(isPresented: $showDatePicker) {
            datePicker
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                datePickerSelection = selectedDay
                showDatePicker = true
            } label: {
                HStack(spacing: 8) {
                    Text(
                        selectedDay.formatted(
                            .dateTime
                                .month(.wide)
                                .day()
                                .year()
                                .locale(locale)
                        )
                    )
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(reduceMotion ? Motion.quick : Motion.standard, value: selectedDay)
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the calendar")

            WeekStrip(
                selectedDay: $selectedDay,
                daysWithEntries: store.daysWithEntries,
                calendar: store.calendar,
                allowedDates: allowedDates
            )
        }
        .padding(.bottom, 4)
    }

    private func daySection(_ day: TimelineDay) -> some View {
        ForEach(day.entries) { entry in
            let route = Route.entry(entry.id)
            NavigationLink(value: route) {
                EntryCard(entry: entry, isBeingRead: store.annotatingEntryIDs.contains(entry.id))
                    .matchedTransitionSource(id: route, in: navigationNamespace) { source in
                        source
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    @ViewBuilder
    private var selectedDayContent: some View {
        if let selectedTimelineDay {
            daySection(selectedTimelineDay)
        } else if store.timeline.isEmpty && store.calendar.isSameDay(selectedDay, .now) {
            emptyState
        } else {
            noEntriesState
        }
    }

    private var dayContentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing here yet.")
                .foregroundStyle(Theme.primaryText)
            Text("Tap the microphone to speak, or hold it to write. Nothing leaves this phone.")
                .foregroundStyle(Theme.secondaryText)
                .font(.subheadline)
        }
        .padding(.top, 40)
    }

    private var noEntriesState: some View {
        Text("No entries on this day.")
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 28)
    }

    private var datePicker: some View {
        NavigationStack {
            DatePicker(
                "Choose a date",
                selection: $datePickerSelection,
                in: allowedDates,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, 16)
            .tint(Theme.accent)
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDatePicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        withAnimation(reduceMotion ? Motion.quick : Motion.standard) {
                            selectedDay = store.calendar.startOfDay(datePickerSelection)
                        }
                        showDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var selectedTimelineDay: TimelineDay? {
        store.timeline.first {
            store.calendar.isSameDay($0.day, selectedDay)
        }
    }

    private var allowedDates: ClosedRange<Date> {
        let components = DateComponents(year: 2000, month: 1, day: 1)
        let earliest = store.calendar.calendar.date(from: components)
            .map(store.calendar.startOfDay)
            ?? Date(timeIntervalSince1970: 946_684_800)
        return earliest...store.calendar.startOfDay(.now)
    }
}
