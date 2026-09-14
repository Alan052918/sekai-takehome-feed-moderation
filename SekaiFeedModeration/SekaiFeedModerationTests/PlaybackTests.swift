import XCTest
@testable import SekaiFeedModeration

@MainActor
final class PlaybackTests: XCTestCase {
    func testPauseCompletesBeforeReplacementPlays() async {
        let coordinator = PlaybackCoordinator()
        let a = FakePlayer(), b = FakePlayer()
        coordinator.update(target: a)
        await drain()
        XCTAssertEqual(a.commands, [true])
        a.delay = true
        coordinator.update(target: b)
        await drain()
        XCTAssertEqual(a.commands, [true, false])
        XCTAssertTrue(b.commands.isEmpty)
        coordinator.update(target: nil)
        a.complete()
        await drain()
        XCTAssertTrue(b.commands.isEmpty)
    }

    func testFailedPauseDisposesBeforeNextPlay() async {
        let coordinator = PlaybackCoordinator()
        let a = FakePlayer(), b = FakePlayer()
        coordinator.update(target: a)
        await drain()
        a.fail = true
        coordinator.update(target: b)
        await drain()
        XCTAssertTrue(a.disposed)
        XCTAssertEqual(b.commands, [true])
    }

    func testTargetChangesDuringPlayAreReconciled() async {
        let coordinator = PlaybackCoordinator()
        let a = FakePlayer(), b = FakePlayer()
        a.delay = true
        coordinator.update(target: a)
        await drain()
        coordinator.update(target: b)
        a.delay = false
        a.complete()
        await drain()
        XCTAssertEqual(a.commands, [true, false])
        XCTAssertEqual(b.commands, [true])
    }

    func testRepeatedTargetDoesNotInterruptInteraction() async {
        let coordinator = PlaybackCoordinator()
        let player = FakePlayer()
        coordinator.update(target: player)
        await drain()
        coordinator.update(target: player)
        await drain()
        XCTAssertEqual(player.commands, [true])
    }

    func testFailedPlayIsReleasedBeforeRecovery() async {
        let coordinator = PlaybackCoordinator()
        let player = FakePlayer(), replacement = FakePlayer()
        player.fail = true
        coordinator.update(target: player)
        await drain()
        XCTAssertTrue(player.disposed)
        coordinator.update(target: replacement)
        await drain()
        XCTAssertEqual(replacement.commands, [true])
    }

    private func drain() async { for _ in 0..<30 { await Task.yield() } }
}

@MainActor
private final class FakePlayer: PlaybackControlling {
    var commands: [Bool] = []
    var delay = false
    var fail = false
    var disposed = false
    var continuation: CheckedContinuation<Void, Error>?
    func command(play: Bool) async throws {
        commands.append(play)
        if fail { throw URLError(.unknown) }
        if delay { try await withCheckedThrowingContinuation { continuation = $0 } }
    }
    func discard() { disposed = true }
    func complete() { continuation?.resume(); continuation = nil }
}
