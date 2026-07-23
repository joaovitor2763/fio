import SwiftUI
import FioKit

// MARK: - Waveform

/// Tight vertical bars mirrored around the midline, newest on the right.
struct WaveformView: View {
    let levels: [Float]
    let isLive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: 3, height: max(4, CGFloat(level) * 80))
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isLive ? 1 : 0.45)
        .animation(.linear(duration: 0.1), value: levels)
        .animation(.easeInOut(duration: 0.25), value: isLive)
    }
}

// MARK: - Week strip

/// Seven day cells, Monday first, dots under days that have entries.
struct WeekStrip: View {
    @Binding var selectedDay: Date
    let daysWithEntries: Set<Date>
    let calendar: JournalCalendar
    let allowedDates: ClosedRange<Date>
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            ForEach(calendar.weekDays(containing: selectedDay), id: \.self) { day in
                dayCell(day)
            }
        }
        .id(calendar.weekStart(containing: selectedDay))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 44 else { return }
                    moveWeek(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.selection, trigger: selectedDay)
        .accessibilityAction(named: Text("Previous week")) {
            moveWeek(by: -1)
        }
        .accessibilityAction(named: Text("Next week")) {
            moveWeek(by: 1)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isSameDay(day, selectedDay)
        let isFuture = day > calendar.startOfDay(.now)
        let hasEntries = daysWithEntries.contains(calendar.startOfDay(day))

        return Button {
            withAnimation(.spring(duration: 0.3)) {
                selectedDay = calendar.startOfDay(day)
            }
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.narrow).locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                Text("\(calendar.dayNumber(of: day))")
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
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func moveWeek(by offset: Int) {
        guard let candidate = calendar.calendar.date(
            byAdding: .day,
            value: offset * 7,
            to: selectedDay
        ) else { return }

        let bounded = min(max(calendar.startOfDay(candidate), allowedDates.lowerBound), allowedDates.upperBound)
        guard !calendar.isSameDay(bounded, selectedDay) else { return }

        withAnimation(.spring(duration: 0.3)) {
            selectedDay = bounded
        }
    }
}

// MARK: - Cards

struct EntryCard: View {
    let entry: Entry
    let isBeingRead: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(entry.createdAt.formatted(date: .omitted, time: .shortened)) · \(entryMetadata)")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                if isBeingRead {
                    ReadingDot()
                }
            }

            Text(entry.timelineLine)
                .font(.callout)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .truncationMode(.tail)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private var entryMetadata: String {
        entry.audioFileName == nil
            ? appLocalized("Text", locale: locale)
            : Formatting.compactDuration(entry.duration)
    }
}

/// A tiny pulse shown while the observer is reading a fresh entry.
struct ReadingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.secondaryText)
            .frame(width: 5, height: 5)
            .opacity(pulsing ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityLabel("Fio is reading this entry")
    }
}

/// The slim card at the top of the timeline when a week has been read back.
struct ReviewTeaserCard: View {
    let review: WeekReview

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
        .background(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

// MARK: - Sparkline

/// A thin line through the week's minutes, a dot per day.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { canvas, size in
            guard values.count > 1 else { return }
            let maximum = max(values.max() ?? 1, 0.001)
            let stepX = size.width / CGFloat(values.count - 1)
            let inset: CGFloat = 6

            func point(_ index: Int) -> CGPoint {
                let normalized = values[index] / maximum
                let y = inset + (1 - CGFloat(normalized)) * (size.height - inset * 2)
                return CGPoint(x: CGFloat(index) * stepX, y: y)
            }

            var path = Path()
            path.move(to: point(0))
            for index in 1..<values.count {
                path.addLine(to: point(index))
            }
            canvas.stroke(path, with: .color(Theme.primaryText.opacity(0.7)), lineWidth: 1)

            for index in values.indices {
                let center = point(index)
                let dot = Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
                canvas.fill(dot, with: .color(Theme.primaryText))
            }
        }
        .accessibilityLabel("Minutes spoken per day this week")
    }
}
