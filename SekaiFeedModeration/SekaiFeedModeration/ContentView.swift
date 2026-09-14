import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FeedViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FeedPager(items: model.visibleItems, active: scenePhase == .active) { id in
                Task { await model.nearEnd(id) }
            }
            if model.visibleItems.isEmpty {
                VStack(spacing: 16) {
                    if model.isLoading { ProgressView().tint(.white) }
                    Text(model.isTerminal ? "You're all caught up" : "Discover sekais")
                        .font(.title2.bold())
                    if let message = model.errorMessage { Text(message).multilineTextAlignment(.center) }
                    if !model.isLoading && !model.isTerminal {
                        Button("Load feed") { Task { await model.loadMore() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .foregroundColor(.white)
            }
        }
        .overlay(alignment: .top) {
            if !model.visibleItems.isEmpty {
                if model.isLoading {
                    ProgressView().tint(.white).padding()
                } else if model.errorMessage != nil || model.needsExplicitLoad {
                    Button(model.errorMessage == nil ? "Load more" : "Couldn't load more · Retry") {
                        Task { await model.loadMore() }
                    }
                    .buttonStyle(.borderedProminent).padding()
                }
            }
        }
        .task { if model.visibleItems.isEmpty { await model.loadMore() } }
    }
}
