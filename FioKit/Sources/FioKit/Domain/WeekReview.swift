import Foundation

/// The Sunday read-back: one completed week, written back to its author.
public struct WeekReview: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    /// Monday of the week this review covers.
    public var weekStart: Date
    public var createdAt: Date
    public var title: String
    public var summary: String
    /// Minutes spoken per day, Monday through Sunday, for the sparkline.
    public var dailyMinutes: [Double]

    public init(
        id: UUID = UUID(),
        weekStart: Date,
        createdAt: Date,
        title: String,
        summary: String,
        dailyMinutes: [Double]
    ) {
        self.id = id
        self.weekStart = weekStart
        self.createdAt = createdAt
        self.title = title
        self.summary = summary
        self.dailyMinutes = dailyMinutes
    }
}
