import Combine
import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private var rawItems: [Sekai] = []
    @Published private(set) var visibleItems: [Sekai] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isTerminal = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var needsExplicitLoad = false
    private var refresh = 0
    private let api: FeedAPI
    private let visibility: VisibilityProviding
    private var subscription: AnyCancellable?

    init(api: FeedAPI, visibility: VisibilityProviding) {
        self.api = api
        self.visibility = visibility
        subscription = $rawItems.combineLatest(visibility.publisher)
            .map { items, snapshot in items.filter(snapshot.includes) }
            .removeDuplicates()
            .sink { [weak self] in self?.visibleItems = $0 }
    }

    func nearEnd(_ id: String) async {
        guard !needsExplicitLoad, errorMessage == nil,
              let index = visibleItems.firstIndex(where: { $0.id == id }),
              index >= visibleItems.count - 3 else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !isTerminal else { return }
        isLoading = true
        errorMessage = nil
        needsExplicitLoad = false
        defer { isLoading = false }
        for attempt in 0..<3 {
            do {
                let page = try await api.feed(limit: 6, refresh: refresh)
                try Task.checkCancellation()
                refresh += 1
                isTerminal = page.count < 6
                var ids = Set(rawItems.map(\.id))
                let appended = page.filter { ids.insert($0.id).inserted }
                rawItems += appended
                if isTerminal || appended.contains(where: visibility.snapshot.includes) { return }
                if attempt == 2 { needsExplicitLoad = true }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "Couldn't load the feed. Check the mock server and try again."
                return
            }
        }
    }
}
