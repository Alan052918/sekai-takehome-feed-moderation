import Foundation

@MainActor
protocol PlaybackControlling: AnyObject {
    func command(play: Bool) async throws
    /// Stop navigation, detach and release the WebView when playback is uncertain.
    func discard()
}

/// All commands, including shutdown, pass through this single serial worker.
@MainActor
final class PlaybackCoordinator {
    private var desired: PlaybackControlling?
    private var playing: PlaybackControlling?
    private var worker: Task<Void, Never>?
    var didReconcile: (() -> Void)?

    func update(target: PlaybackControlling?) {
        guard desired !== target else { return }
        desired = target
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.reconcile() }
    }

    func isBusy(with player: PlaybackControlling) -> Bool {
        playing === player
    }

    private func reconcile() async {
        while true {
            if let previous = playing, previous !== desired {
                do { try await previous.command(play: false) }
                catch { previous.discard() }
                playing = nil
                continue
            }
            if playing == nil, let next = desired {
                // Reserve before awaiting: a pending play must also be shut down.
                playing = next
                do { try await next.command(play: true) }
                catch {
                    // Play may have partially executed; discard before another play.
                    next.discard()
                    playing = nil
                    if desired === next { desired = nil }
                }
                continue
            }
            break
        }
        worker = nil
        didReconcile?()
    }
}
