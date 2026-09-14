import WebKit

/// A slot never changes identity. Eviction destroys its WebView after command shutdown.
/// Fresh slots use fresh generations and delegates, so recycled loads cannot play.
@MainActor
final class WebSlot: NSObject, WKNavigationDelegate, PlaybackControlling {
    let item: Sekai
    let generation = UUID()
    private(set) var webView: WKWebView?
    private(set) var ready = false
    private(set) var loading = false
    private(set) var failed = false
    var changed: (() -> Void)?
    var terminated: (() -> Void)?
    private var navigation: WKNavigation?

    init(item: Sekai) {
        self.item = item
        super.init()
        let webView = WKWebView()
        WebViewLifetime.track(webView)
        webView.navigationDelegate = self
        self.webView = webView
    }

    func load() {
        guard let webView, webView.window != nil, !loading, !ready, !failed else { return }
        loading = true
        navigation = webView.load(URLRequest(url: item.gameURL))
        let expectedNavigation = navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.loading, self.navigation === expectedNavigation else { return }
            if ProcessInfo.processInfo.environment["SEKAI_MEASURE"] == "1" {
                print("WEB_TIMEOUT \(self.item.id) progress=\(self.webView?.estimatedProgress ?? -1) url=\(String(describing: self.webView?.url))")
            }
            self.discard()
        }
    }

    func cancelLoad() {
        guard loading else { return }
        navigation = nil
        loading = false
        webView?.stopLoading()
    }

    func command(play: Bool) async throws {
        guard let webView, ready else { throw URLError(.cancelled) }
        // Timeout prevents a hung WebContent process from pinning the serial worker.
        try await withCheckedThrowingContinuation { continuation in
            let completion = JavaScriptCompletion(continuation)
            webView.evaluateJavaScript(play ? "window.sekaiPlay()" : "window.sekaiPause()") { _, error in
                if let error { completion.finish(.failure(error)) }
                else { completion.finish(.success(())) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                completion.finish(.failure(URLError(.timedOut)))
            }
        }
    }

    func discard() {
        ready = false
        loading = false
        failed = true
        navigation = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        changed?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, self.navigation === navigation else { return }
        loading = false
        ready = true
        changed?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(webView, navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(webView, navigation)
    }

    private func fail(_ webView: WKWebView, _ navigation: WKNavigation?) {
        guard self.webView === webView, self.navigation === navigation else { return }
        discard()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        discard()
        terminated?()
    }
}

@MainActor
private final class JavaScriptCompletion {
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
