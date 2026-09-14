import XCTest
@testable import SekaiFeedModeration

@MainActor
final class APITests: XCTestCase {
    func testFeedDecodesBareArrayAndUsesWireQuery() async throws {
        let session = makeSession()
        FeedURLProtocol.status = 200
        FeedURLProtocol.body = Data(#"[{"game_id":"g","title":"Game","game_url":"http://localhost:8787/content/g","creator_id":"c","creator_name":"Name","like_count":7}]"#.utf8)
        let api = SekaiAPIClient(baseURL: URL(string: "http://localhost:8787")!, session: session)
        let result = try await api.feed(limit: 6, refresh: 2)
        XCTAssertEqual(result.first?.id, "g")
        XCTAssertEqual(result.first?.creatorID, "c")
        XCTAssertEqual(result.first?.likeCount, 7)
        let request = try XCTUnwrap(FeedURLProtocol.request)
        XCTAssertEqual(request.url?.path, "/game/feed")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query, [URLQueryItem(name: "limit", value: "6"), URLQueryItem(name: "refresh", value: "2")])
    }

    func testHTTPFailureDoesNotDecodeSuccessBody() async {
        FeedURLProtocol.status = 503
        FeedURLProtocol.body = Data("[]".utf8)
        let api = SekaiAPIClient(baseURL: URL(string: "http://localhost:8787")!, session: makeSession())
        do {
            _ = try await api.feed(limit: 6, refresh: 0)
            XCTFail("HTTP failure must be surfaced")
        } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
    }

    func testBlockUsesWireEndpointAndJSONPayload() async throws {
        FeedURLProtocol.status = 200
        FeedURLProtocol.body = Data(#"{"code":0,"message":"ok","data":null}"#.utf8)
        let api = SekaiAPIClient(baseURL: URL(string: "http://localhost:8787")!, session: makeSession())

        try await api.blockCreator("creator_1")

        let request = try XCTUnwrap(FeedURLProtocol.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/user/block/v1/blockUser")
        let payload = try XCTUnwrap(FeedURLProtocol.requestBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: payload) as? [String: String], ["user_id": "creator_1"])
    }

    func testReportUsesWireEndpointAndSpamPayload() async throws {
        FeedURLProtocol.status = 200
        FeedURLProtocol.body = Data(#"{"code":0,"message":"ok","data":null}"#.utf8)
        let api = SekaiAPIClient(baseURL: URL(string: "http://localhost:8787")!, session: makeSession())

        try await api.reportContent("game_42", reason: "spam")

        let request = try XCTUnwrap(FeedURLProtocol.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/report/content/v1/reportContent")
        let payload = try XCTUnwrap(FeedURLProtocol.requestBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: payload) as? [String: String], ["game_id": "game_42", "reason": "spam"])
    }

    func testModerationRejectsNonzeroBackendCode() async {
        FeedURLProtocol.status = 200
        FeedURLProtocol.body = Data(#"{"code":50001,"message":"planned failure","data":null}"#.utf8)
        let api = SekaiAPIClient(baseURL: URL(string: "http://localhost:8787")!, session: makeSession())

        do {
            try await api.blockCreator("creator_1")
            XCTFail("A nonzero backend code must fail delivery")
        } catch is SekaiAPIError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class FeedURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var requestBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        Self.requestBody = request.httpBody ?? readBodyStream(request.httpBodyStream)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            result.append(contentsOf: buffer[0..<count])
        }
        return result
    }
}
