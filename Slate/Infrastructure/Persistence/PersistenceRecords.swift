import Foundation
import SwiftData
import SlateKit

// SwiftData records are an infrastructure detail: they mirror the domain
// entities 1:1 and never leak past the repositories.

@Model
final class EntryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var headline: String
    var observations: [String]
    var tags: [String]
    var authorContext: String

    init(from entry: Entry) {
        id = entry.id
        createdAt = entry.createdAt
        duration = entry.duration
        transcript = entry.transcript.text
        headline = entry.reflection.headline
        observations = entry.reflection.observations
        tags = entry.reflection.tags
        authorContext = entry.authorContext
    }

    func apply(_ entry: Entry) {
        createdAt = entry.createdAt
        duration = entry.duration
        transcript = entry.transcript.text
        headline = entry.reflection.headline
        observations = entry.reflection.observations
        tags = entry.reflection.tags
        authorContext = entry.authorContext
    }

    var asDomain: Entry {
        Entry(
            id: id,
            createdAt: createdAt,
            duration: duration,
            transcript: Transcript(transcript),
            reflection: Reflection(headline: headline, observations: observations, tags: tags),
            authorContext: authorContext
        )
    }
}

@Model
final class ReviewRecord {
    @Attribute(.unique) var id: UUID
    var weekStart: Date
    var createdAt: Date
    var title: String
    var summary: String
    var dailyMinutes: [Double]

    init(from review: WeekReview) {
        id = review.id
        weekStart = review.weekStart
        createdAt = review.createdAt
        title = review.title
        summary = review.summary
        dailyMinutes = review.dailyMinutes
    }

    func apply(_ review: WeekReview) {
        weekStart = review.weekStart
        createdAt = review.createdAt
        title = review.title
        summary = review.summary
        dailyMinutes = review.dailyMinutes
    }

    var asDomain: WeekReview {
        WeekReview(
            id: id,
            weekStart: weekStart,
            createdAt: createdAt,
            title: title,
            summary: summary,
            dailyMinutes: dailyMinutes
        )
    }
}
