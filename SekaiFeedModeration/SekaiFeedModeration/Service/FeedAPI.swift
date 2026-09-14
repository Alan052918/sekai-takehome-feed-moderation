@MainActor
protocol FeedAPI {
    func feed(limit: Int, refresh: Int) async throws -> [Sekai]
}
