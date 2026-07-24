import SwiftUI
import FioKit

extension InsightsScreen {
    var activitySection: some View {
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
        .redacted(reason: store.isUsageStatisticsReady ? [] : .placeholder)
    }

    var speakingHoursSection: some View {
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
        .redacted(reason: store.isUsageStatisticsReady ? [] : .placeholder)
    }

    var privacyNote: some View {
        Label(
            "These insights are calculated on this iPhone from your journal. Nothing is uploaded.",
            systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(Theme.tertiaryText)
    }

    func sectionHeader(_ title: LocalizedStringKey, detail: String? = nil) -> some View {
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

    func activityCell(for day: Date) -> some View {
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

    func activityLevel(duration: TimeInterval) -> Int {
        switch duration {
        case ...0: 0
        case ...120: 1
        case ...300: 2
        case ...900: 3
        default: 4
        }
    }

    func activityColor(level: Int) -> Color {
        switch level {
        case 1: Theme.primaryText.opacity(0.18)
        case 2: Theme.primaryText.opacity(0.38)
        case 3: Theme.primaryText.opacity(0.65)
        case 4: Theme.primaryText
        default: Theme.card
        }
    }

    var activityWeeks: [ActivityWeek] {
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

    func hourBarHeight(count: Int) -> CGFloat {
        let maximum = max(statistics.hourlyRecordingCounts.max() ?? 0, 1)
        return 5 + (CGFloat(count) / CGFloat(maximum)) * 72
    }

    func hourRange(_ hour: Int) -> String {
        var startComponents = DateComponents()
        startComponents.hour = hour
        var endComponents = DateComponents()
        endComponents.hour = (hour + 1) % 24
        let start = calendar.calendar.date(from: startComponents) ?? .now
        let end = calendar.calendar.date(from: endComponents) ?? .now
        return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }

    func usageDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
