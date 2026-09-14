import Combine
import Foundation

/// The sole app-scoped mutable moderation state. Visibility is updated before delivery is attempted.
@MainActor
final class ModerationStore: ObservableObject, VisibilityProviding {
    private enum Keys {
        static let blockedCreatorIDs = "moderation.blockedCreatorIDs"
        static let reportedGameIDs = "moderation.reportedGameIDs"
    }

    private let api: ModerationAPI
    private let defaults: UserDefaults
    private let feedbackSubject = PassthroughSubject<ModerationFeedback, Never>()
    private var deliveryTasks: [UUID: Task<Void, Never>] = [:]

    @Published private(set) var snapshot: VisibilitySnapshot
    var publisher: AnyPublisher<VisibilitySnapshot, Never> { $snapshot.eraseToAnyPublisher() }
    var feedback: AnyPublisher<ModerationFeedback, Never> { feedbackSubject.eraseToAnyPublisher() }

    init(api: ModerationAPI, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        snapshot = VisibilitySnapshot(
            blockedCreatorIDs: Set(defaults.stringArray(forKey: Keys.blockedCreatorIDs) ?? []),
            reportedGameIDs: Set(defaults.stringArray(forKey: Keys.reportedGameIDs) ?? [])
        )
    }

    func blockCreator(_ creatorID: String) {
        guard !creatorID.isEmpty else { return }
        var updated = snapshot
        guard updated.blockedCreatorIDs.insert(creatorID).inserted else { return }
        publish(updated)
        feedbackSubject.send(.creatorBlocked)
        submit { try await self.api.blockCreator(creatorID) }
    }

    func reportContent(_ gameID: String) {
        guard !gameID.isEmpty else { return }
        var updated = snapshot
        guard updated.reportedGameIDs.insert(gameID).inserted else { return }
        publish(updated)
        feedbackSubject.send(.contentHidden)
        submit { try await self.api.reportContent(gameID, reason: "spam") }
    }

    private func publish(_ updated: VisibilitySnapshot) {
        defaults.set(updated.blockedCreatorIDs.sorted(), forKey: Keys.blockedCreatorIDs)
        defaults.set(updated.reportedGameIDs.sorted(), forKey: Keys.reportedGameIDs)
        snapshot = updated
    }

    private func submit(_ operation: @escaping @MainActor () async throws -> Void) {
        let id = UUID()
        deliveryTasks[id] = Task { [weak self] in
            do {
                try await operation()
            } catch {
                self?.feedbackSubject.send(.deliveryFailed)
            }
            self?.deliveryTasks[id] = nil
        }
    }
}
