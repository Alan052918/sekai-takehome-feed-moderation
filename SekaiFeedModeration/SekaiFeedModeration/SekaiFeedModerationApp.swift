import SwiftUI

@main
struct SekaiFeedModerationApp: App {
    @StateObject private var feed: FeedViewModel

    init() {
        let api = SekaiAPIClient(baseURL: URL(string: "http://127.0.0.1:8787")!)
        _feed = StateObject(wrappedValue: FeedViewModel(api: api, visibility: FeedVisibility()))
    }

    var body: some Scene {
        WindowGroup { ContentView(model: feed).preferredColorScheme(.dark) }
    }
}
