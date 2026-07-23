import Foundation
import SwiftData

/// The Sunday read-back: one completed week, written back to its author.
@Model
final class WeeklyReview {
    /// Monday of the week this review covers.
    var weekStart: Date
    var createdAt: Date
    var title: String
    var summary: String
    /// Minutes spoken per day, Monday through Sunday, for the sparkline.
    var dailyMinutes: [Double]

    init(weekStart: Date, createdAt: Date = .now, title: String, summary: String, dailyMinutes: [Double]) {
        self.weekStart = weekStart
        self.createdAt = createdAt
        self.title = title
        self.summary = summary
        self.dailyMinutes = dailyMinutes
    }
}
