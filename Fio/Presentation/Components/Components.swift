import SwiftUI
import Charts
import FioKit

// MARK: - Topics

/// A compact wrapping layout for topic pills at larger Dynamic Type sizes too.
struct WrapLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var y: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                y += row.height + spacing
                row = Row(y: y)
            }
            row.indices.append(index)
            row.width += size.width + (row.indices.count > 1 ? spacing : 0)
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

struct TopicPill: View {
    let name: String
    var isSuggested = false
    var isSelected = false

    var body: some View {
        HStack(spacing: 5) {
            if isSuggested {
                Image(systemName: "sparkles")
                    .font(.caption2)
            }
            Text(name)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    isSuggested || isSelected
                        ? Theme.accent.opacity(isSelected ? 0.18 : 0.10)
                        : Theme.background
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    isSuggested || isSelected
                        ? Theme.accent.opacity(isSelected ? 0.70 : 0.45)
                        : Theme.cardStroke,
                    lineWidth: 1
                )
        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Theme.secondaryText)
            .frame(width: 5, height: 5)
            .opacity(pulsing && !reduceMotion ? 0.25 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = !reduceMotion }
            .onChange(of: reduceMotion) { _, shouldReduce in
                pulsing = !shouldReduce
            }
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

/// Appears only while a newly discovered thread is waiting for review.
struct DreamTeaserCard: View {
    let topic: Topic

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.callout)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Fio found something recurring")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                Text(topic.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                Text("\(topic.entryIDs.count) connected entries")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.accent.opacity(0.38), lineWidth: 1)
        )
    }
}

// MARK: - Weekly activity

/// A contextual chart of the week's speaking rhythm, Monday through Sunday.
struct WeeklyActivityChart: View {
    let weekStart: Date
    let values: [Double]
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct DayPoint: Identifiable {
        let index: Int
        let date: Date
        let minutes: Double

        var id: Int { index }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metricHeader

            Chart(dayPoints) { point in
                AreaMark(
                    x: .value("Day", point.index),
                    y: .value("Minutes", point.minutes)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(0.28),
                            Theme.accent.opacity(0.015)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.index),
                    y: .value("Minutes", point.minutes)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Theme.primaryText.opacity(0.82))

                PointMark(
                    x: .value("Day", point.index),
                    y: .value("Minutes", point.minutes)
                )
                .symbolSize(point.minutes > 0 ? 42 : 22)
                .foregroundStyle(
                    point.minutes > 0
                        ? Theme.accent
                        : Theme.tertiaryText.opacity(0.45)
                )
            }
            .chartXScale(domain: 0...max(values.count - 1, 1))
            .chartYScale(domain: 0...chartMaximum)
            .chartXAxis {
                AxisMarks(values: dayPoints.map(\.index)) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self),
                           let point = dayPoints.first(where: { $0.index == index }) {
                            Text(
                                point.date.formatted(
                                    .dateTime.weekday(.narrow).locale(locale)
                                )
                            )
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 128)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.cardStroke.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly speaking activity")
        .accessibilityValue(
            "\(totalDuration) recorded across \(activeDayCount) active days"
        )
    }

    @ViewBuilder
    private var metricHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                durationMetric
                activeDaysMetric(alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                durationMetric
                Spacer(minLength: 8)
                activeDaysMetric(alignment: .trailing)
            }
        }
    }

    private var durationMetric: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(totalDuration)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
            Text("recorded this week")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func activeDaysMetric(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text("\(activeDayCount)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
            Text(activeDayCount == 1 ? "active day" : "active days")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var dayPoints: [DayPoint] {
        values.enumerated().map { index, minutes in
            DayPoint(
                index: index,
                date: Calendar.autoupdatingCurrent.date(
                    byAdding: .day,
                    value: index,
                    to: weekStart
                ) ?? weekStart,
                minutes: max(minutes, 0)
            )
        }
    }

    private var activeDayCount: Int {
        values.filter { $0 > 0 }.count
    }

    private var chartMaximum: Double {
        max((values.max() ?? 0) * 1.18, 1)
    }

    private var totalDuration: String {
        let totalMinutes = max(values.reduce(0, +), 0)
        if totalMinutes < 1 {
            return totalMinutes > 0 ? "<1 min" : "0 min"
        }
        if totalMinutes < 60 {
            return "\(Int(totalMinutes.rounded())) min"
        }

        let roundedMinutes = Int(totalMinutes.rounded())
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}
