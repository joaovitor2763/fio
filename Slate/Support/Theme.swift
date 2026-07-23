import SwiftUI

enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.10)
    static let cardStroke = Color(white: 0.17)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.56)
    static let tertiaryText = Color(white: 0.38)
}

extension TimeInterval {
    /// "1m 34s" — the duration style used on timeline cards.
    var compactDuration: String {
        let total = Int(rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes == 0 { return "\(seconds)s" }
        return "\(minutes)m \(seconds)s"
    }

    /// "1:53" — the running clock on the record screen.
    var clock: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Int {
    /// 13 -> "th", 21 -> "st"
    var ordinalSuffix: String {
        if (11...13).contains(self % 100) { return "th" }
        switch self % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

extension Calendar {
    /// Slate's weeks run Monday through Sunday; the review lands on Sunday.
    static let mondayFirst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()
}

extension Date {
    /// "Mon July 13th, 2026" — the entry screen title.
    var entryTitle: String {
        let calendar = Calendar.mondayFirst
        let day = calendar.component(.day, from: self)
        let weekday = formatted(.dateTime.weekday(.abbreviated))
        let month = formatted(.dateTime.month(.wide))
        let year = calendar.component(.year, from: self)
        return "\(weekday) \(month) \(day)\(day.ordinalSuffix), \(year)"
    }
}

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
            if !current.indices.isEmpty, current.width + size.width > maxWidth {
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
