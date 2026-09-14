import Foundation

enum SekaiAPIError: Error {
    case rejectedByBackend
}

struct SekaiAPIClient: FeedAPI, ModerationAPI {
    let baseURL: URL
    var session: URLSession = .shared

    func feed(limit: Int, refresh: Int) async throws -> [Sekai] {
        var components = URLComponents(url: baseURL.appendingPathComponent("game/feed"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "refresh", value: String(refresh))]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Sekai].self, from: data)
    }

    func blockCreator(_ creatorID: String) async throws {
        try await post(path: "api/user/block/v1/blockUser", payload: ["user_id": creatorID])
    }

    func reportContent(_ gameID: String, reason: String) async throws {
        try await post(path: "api/report/content/v1/reportContent", payload: ["game_id": gameID, "reason": reason])
    }

    private func post(path: String, payload: [String: String]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard envelope.code == 0 else { throw SekaiAPIError.rejectedByBackend }
    }
}

private struct ResponseEnvelope: Decodable {
    let code: Int
}
