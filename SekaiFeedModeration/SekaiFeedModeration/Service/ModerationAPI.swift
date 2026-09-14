@MainActor
protocol ModerationAPI {
    func blockCreator(_ creatorID: String) async throws
    func reportContent(_ gameID: String, reason: String) async throws
}
