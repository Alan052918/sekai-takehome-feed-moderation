import SwiftUI

struct FeedView: View {
    @ObservedObject var model: FeedViewModel
    @ObservedObject var moderation: ModerationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FeedPager(
                items: model.visibleItems,
                active: scenePhase == .active,
                nearEnd: { id in Task { await model.nearEnd(id) } },
                reportContent: { moderation.reportContent($0) },
                blockCreator: { moderation.blockCreator($0) }
            )
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
        .onReceive(moderation.feedback) { feedback in
            let message = feedback.message
            toastMessage = message
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if toastMessage == message { toastMessage = nil }
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }
}
