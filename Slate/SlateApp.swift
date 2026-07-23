import SwiftUI
import SwiftData

@main
struct SlateApp: App {
    let container: ModelContainer = {
        let schema = Schema([JournalEntry.self, WeeklyReview.self])
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
