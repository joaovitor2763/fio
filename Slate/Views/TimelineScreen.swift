import SwiftUI
import SwiftData

/// The journal: a large date, the week strip, and every entry in reverse order.
struct TimelineScreen: View {
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \WeeklyReview.weekStart, order: .reverse) private var reviews: [WeeklyReview]

    @State private var selectedDay = Calendar.mondayFirst.startOfDay(for: .now)

    private var calendar: Calendar { .mondayFirst }

    private var days: [(day: Date, entries: [JournalEntry])] {
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                    header

                    if let latest = reviews.first {
                        NavigationLink(value: latest.persistentModelID) {
                            ReviewTeaserCard(review: latest)
                        }
                        .buttonStyle(.plain)
                    }

                    if days.isEmpty {
                        emptyState
                    }

                    ForEach(days, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                NavigationLink(value: entry.persistentModelID) {
                                    EntryCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            if !calendar.isDate(group.day, inSameDayAs: selectedDay) {
                                Text(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.tertiaryText)
                                    .padding(.top, 10)
                            }
                        }
                        .id(group.day)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 90)
            }
            .onChange(of: selectedDay) { _, day in
                if days.contains(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                    withAnimation { proxy.scrollTo(calendar.startOfDay(for: day), anchor: .top) }
                }
            }
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ReviewListScreen()
                } label: {
                    Image(systemName: "text.book.closed")
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Weekly reviews")
            }
        }
        .navigationDestination(for: PersistentIdentifier.self) { id in
            DestinationResolver(id: id)
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(selectedDay.formatted(.dateTime.month(.wide).day().year()))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 8)

            WeekStrip(
                selectedDay: $selectedDay,
                daysWithEntries: Set(days.map(\.day))
            )
        }
        .padding(.bottom, 4)
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

/// Resolves a tapped model ID to the right destination screen.
private struct DestinationResolver: View {
    @Environment(\.modelContext) private var context
    let id: PersistentIdentifier

    var body: some View {
        if let entry = context.model(for: id) as? JournalEntry {
            EntryDetailScreen(entry: entry)
        } else if let review = context.model(for: id) as? WeeklyReview {
            ReviewScreen(review: review)
        }
    }
}

/// Seven day cells, Monday first, dots under days that have entries.
struct WeekStrip: View {
    @Binding var selectedDay: Date
    let daysWithEntries: Set<Date>

    private var calendar: Calendar { .mondayFirst }

    private var weekDays: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(weekDays, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isFuture = day > calendar.startOfDay(for: .now)
        let hasEntries = daysWithEntries.contains(calendar.startOfDay(for: day))

        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isFuture ? Theme.tertiaryText : Theme.primaryText)
                Circle()
                    .fill(hasEntries ? Theme.secondaryText : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primaryText : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}

struct EntryCard: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(entry.createdAt.formatted(date: .omitted, time: .shortened)) · \(entry.duration.compactDuration)")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)

            Text(entry.timelineLine)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)

            if !entry.tags.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        TagCapsule(text: tag)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.card)
        )
    }
}

/// The slim card at the top of the timeline when a week has been read back.
struct ReviewTeaserCard: View {
    let review: WeeklyReview

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your week, read back · \(review.weekStart.formatted(.dateTime.month(.wide).day()))")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                Text(review.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}
