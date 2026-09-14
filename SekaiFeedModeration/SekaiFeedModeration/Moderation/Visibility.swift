import Combine

struct VisibilitySnapshot: Equatable {
    var blockedCreatorIDs: Set<String> = []
    var reportedGameIDs: Set<String> = []

    func includes(_ item: Sekai) -> Bool {
        !blockedCreatorIDs.contains(item.creatorID) && !reportedGameIDs.contains(item.id)
    }
}

@MainActor
protocol VisibilityProviding {
    var snapshot: VisibilitySnapshot { get }
    var publisher: AnyPublisher<VisibilitySnapshot, Never> { get }
}
