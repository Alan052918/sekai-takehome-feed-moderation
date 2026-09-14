import XCTest
import Combine
@testable import SekaiFeedModeration

@MainActor
final class SekaiFeedModerationTests: XCTestCase {
    func testRawPageControlsCursorAndDeduplicates() async {
        let api = FakeAPI(pages: [Array(repeating: item("a"), count: 6), [item("b")]])
        let model = FeedViewModel(api: api, visibility: FeedVisibility())
        await model.loadMore()
        XCTAssertEqual(model.visibleItems.map(\.id), ["a"])
        XCTAssertFalse(model.isTerminal)
        await model.loadMore()
        XCTAssertEqual(api.requests, [0, 1])
        XCTAssertEqual(model.visibleItems.map(\.id), ["a", "b"])
        XCTAssertTrue(model.isTerminal)
    }

    func testHiddenPagesAreBoundedAndFutureItemsStayHidden() async {
        let visibility = FeedVisibility()
        visibility.subject.send(VisibilitySnapshot(blockedCreatorIDs: ["creator"], reportedGameIDs: []))
        let api = FakeAPI(pages: (0..<4).map { page in (0..<6).map { item("\(page)-\($0)") } })
        let model = FeedViewModel(api: api, visibility: visibility)
        await model.loadMore()
        XCTAssertEqual(api.requests, [0, 1, 2])
        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertTrue(model.needsExplicitLoad)
        visibility.subject.send(VisibilitySnapshot())
        XCTAssertEqual(model.visibleItems.count, 18)
    }

    func testFailedPageRetriesSameCursor() async {
        let api = FakeAPI(pages: [[item("a")]])
        api.fail = true
        let model = FeedViewModel(api: api, visibility: FeedVisibility())
        await model.loadMore()
        XCTAssertNotNil(model.errorMessage)
        api.fail = false
        await model.loadMore()
        XCTAssertEqual(api.requests, [0, 0])
        XCTAssertEqual(model.visibleItems.count, 1)
    }
}

@MainActor
private final class FakeAPI: FeedAPI {
    var pages: [[Sekai]]
    var requests: [Int] = []
    var fail = false
    init(pages: [[Sekai]]) { self.pages = pages }
    func feed(limit: Int, refresh: Int) async throws -> [Sekai] {
        XCTAssertEqual(limit, 6)
        requests.append(refresh)
        if fail { throw URLError(.cannotConnectToHost) }
        return pages[refresh]
    }
}

private func item(_ id: String) -> Sekai {
    Sekai(id: id, title: id, gameURL: URL(string: "http://localhost/\(id)")!, creatorID: "creator", creatorName: "Creator", likeCount: 0)
}
