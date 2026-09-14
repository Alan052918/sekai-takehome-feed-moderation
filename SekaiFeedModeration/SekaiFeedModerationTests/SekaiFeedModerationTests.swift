import XCTest
import Combine
@testable import SekaiFeedModeration

@MainActor
final class SekaiFeedModerationTests: XCTestCase {
    func testBlockingHidesMatchingCreatorImmediatelyAndPersists() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let api = ModerationFakeAPI()
        api.suspendRequests = true
        let store = ModerationStore(api: api, defaults: defaults)
        let feed = FeedViewModel(api: FakeAPI(pages: [[item("hidden")]]), visibility: store)

        store.blockCreator("creator")

        XCTAssertEqual(store.snapshot.blockedCreatorIDs, ["creator"])
        XCTAssertFalse(store.snapshot.includes(item("hidden")))
        await feed.loadMore()
        XCTAssertTrue(feed.visibleItems.isEmpty)
        let restored = ModerationStore(api: ModerationFakeAPI(), defaults: defaults)
        XCTAssertEqual(restored.snapshot.blockedCreatorIDs, ["creator"])
    }

    func testFailedReportStaysHiddenAndPublishesDeliveryFailure() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let api = ModerationFakeAPI()
        api.reportError = URLError(.cannotConnectToHost)
        let store = ModerationStore(api: api, defaults: defaults)
        var notices: [ModerationFeedback] = []
        let subscription = store.feedback.sink { notices.append($0) }
        defer { subscription.cancel() }

        store.reportContent("game")
        XCTAssertEqual(store.snapshot.reportedGameIDs, ["game"])
        XCTAssertFalse(store.snapshot.includes(item("game")))
        await drain()

        XCTAssertEqual(api.reportRequests.count, 1)
        XCTAssertEqual(api.reportRequests.first?.0, "game")
        XCTAssertEqual(api.reportRequests.first?.1, "spam")
        XCTAssertEqual(notices, [.contentHidden, .deliveryFailed])
        XCTAssertEqual(store.snapshot.reportedGameIDs, ["game"])
        let restored = ModerationStore(api: ModerationFakeAPI(), defaults: defaults)
        XCTAssertEqual(restored.snapshot.reportedGameIDs, ["game"])
    }

    func testDuplicateModerationDoesNotSubmitTwice() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let api = ModerationFakeAPI()
        let store = ModerationStore(api: api, defaults: defaults)

        store.blockCreator("creator")
        store.blockCreator("creator")
        store.reportContent("game")
        store.reportContent("game")
        await drain()

        XCTAssertEqual(api.blockRequests, ["creator"])
        XCTAssertEqual(api.reportRequests.count, 1)
    }

    func testRawPageControlsCursorAndDeduplicates() async {
        let api = FakeAPI(pages: [Array(repeating: item("a"), count: 6), [item("b")]])
        let model = FeedViewModel(api: api, visibility: TestVisibility())
        await model.loadMore()
        XCTAssertEqual(model.visibleItems.map(\.id), ["a"])
        XCTAssertFalse(model.isTerminal)
        await model.loadMore()
        XCTAssertEqual(api.requests, [0, 1])
        XCTAssertEqual(model.visibleItems.map(\.id), ["a", "b"])
        XCTAssertTrue(model.isTerminal)
    }

    func testHiddenPagesAreBoundedAndFutureItemsStayHidden() async {
        let visibility = TestVisibility()
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
        let model = FeedViewModel(api: api, visibility: TestVisibility())
        await model.loadMore()
        XCTAssertNotNil(model.errorMessage)
        api.fail = false
        await model.loadMore()
        XCTAssertEqual(api.requests, [0, 0])
        XCTAssertEqual(model.visibleItems.count, 1)
    }
}

@MainActor
private final class ModerationFakeAPI: ModerationAPI {
    var blockRequests: [String] = []
    var reportRequests: [(String, String)] = []
    var reportError: Error?
    var suspendRequests = false

    func blockCreator(_ creatorID: String) async throws {
        blockRequests.append(creatorID)
        if suspendRequests { try await Task.sleep(nanoseconds: 1_000_000_000) }
    }

    func reportContent(_ gameID: String, reason: String) async throws {
        reportRequests.append((gameID, reason))
        if let reportError { throw reportError }
    }
}

@MainActor
private func drain() async {
    for _ in 0..<30 { await Task.yield() }
}

private let defaultsSuiteName = "SekaiFeedModerationTests.Moderation"

private func makeDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: defaultsSuiteName)!
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    return defaults
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

@MainActor
private final class TestVisibility: VisibilityProviding {
    let subject = CurrentValueSubject<VisibilitySnapshot, Never>(VisibilitySnapshot())
    var snapshot: VisibilitySnapshot { subject.value }
    var publisher: AnyPublisher<VisibilitySnapshot, Never> { subject.eraseToAnyPublisher() }
}

private func item(_ id: String) -> Sekai {
    Sekai(id: id, title: id, gameURL: URL(string: "http://localhost/\(id)")!, creatorID: "creator", creatorName: "Creator", likeCount: 0)
}
