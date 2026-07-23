import SwiftUI
import SlateKit

// MARK: - Tags

/// A minimal wrapping layout for tag capsules.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, in: proposal.width ?? .infinity)
        let height = rows.last.map { $0.origin.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.origin.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var origin: CGPoint = .zero
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var y: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > maxWidth {
                rows.append(current)
                y += current.height + spacing
                current = Row(origin: CGPoint(x: 0, y: y))
            }
            if current.indices.isEmpty { current.origin.y = y }
            current.indices.append(index)
            current.width += size.width + (current.indices.count > 1 ? spacing : 0)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

struct TagCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }
}

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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(calendar.weekDays(containing: selectedDay), id: \.self) { day in
                dayCell(day)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
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
                Text(day.formatted(.dateTime.weekday(.narrow)))
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
}

// MARK: - Cards

struct EntryCard: View {
    let entry: Entry
    let isBeingRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\(entry.createdAt.formatted(date: .omitted, time: .shortened)) · \(Formatting.compactDuration(entry.duration))")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                if isBeingRead {
                    ReadingDot()
                }
            }

            Text(entry.timelineLine)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)

            if !entry.reflection.tags.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(entry.reflection.tags, id: \.self) { tag in
                        TagCapsule(text: tag)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
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
            .accessibilityLabel("Slate is reading this entry")
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
            canvas.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1)

            for index in values.indices {
                let center = point(index)
                let dot = Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
                canvas.fill(dot, with: .color(.white))
            }
        }
        .accessibilityLabel("Minutes spoken per day this week")
    }
}
