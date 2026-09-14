import UIKit
import WebKit

/// Opt-in early measurement. Display-link intervals measure main-thread scheduling,
/// not GPU presentation or separate WebContent memory. Enable SEKAI_MEASURE=1.
@MainActor
final class FeedPerformanceProbe: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var intervals: [Double] = []
    private var overBudget = 0
    private var swipes = 0
    private let enabled = ProcessInfo.processInfo.environment["SEKAI_MEASURE"] == "1"

    func begin() {
        guard enabled, link == nil else { return }
        lastTimestamp = nil
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func end() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        swipes += 1
        let sorted = intervals.sorted()
        guard !sorted.isEmpty else { return }
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print("FEED_METRICS swipes=\(swipes) samples=\(sorted.count) p95_ms=\(p95 * 1000) max_ms=\(sorted.last! * 1000) over_budget=\(overBudget) peak_webviews=\(WebViewLifetime.peakCount)")
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }
        let elapsed = link.timestamp - lastTimestamp
        // Bound storage even during long manual profiling sessions.
        if intervals.count < 100_000 { intervals.append(elapsed) }
        if elapsed > (link.targetTimestamp - link.timestamp) * 1.5 { overBudget += 1 }
    }
}

/// Associated lifetime token avoids subclassing WebKit's view.
final class WebViewLifetime {
    nonisolated(unsafe) static var liveCount = 0
    nonisolated(unsafe) static var peakCount = 0
    nonisolated(unsafe) private static var associationKey: UInt8 = 0

    static func track(_ webView: WKWebView) {
        objc_setAssociatedObject(webView, &associationKey, WebViewLifetime(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    private init() {
        Self.liveCount += 1
        Self.peakCount = max(Self.peakCount, Self.liveCount)
        assert(Self.liveCount <= 3, "Feed exceeded its WebView budget")
    }
    deinit {
        Self.liveCount -= 1
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .feedWebViewReleased, object: nil)
        }
    }
}

extension Notification.Name {
    static let feedWebViewReleased = Notification.Name("FeedWebViewReleased")
}
