import SwiftUI

@main
struct SekaiFeedModerationApp: App {
    @StateObject private var feed: FeedViewModel
    @StateObject private var moderation: ModerationStore

    init() {
        let api = SekaiAPIClient(baseURL: URL(string: "http://127.0.0.1:8787")!)
        let moderation = ModerationStore(api: api)
        _moderation = StateObject(wrappedValue: moderation)
        _feed = StateObject(wrappedValue: FeedViewModel(api: api, visibility: moderation))
    }

    var body: some Scene {
        WindowGroup { FeedView(model: feed, moderation: moderation).preferredColorScheme(.dark) }
    }
}
