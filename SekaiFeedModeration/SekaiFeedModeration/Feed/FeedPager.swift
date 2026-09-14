import SwiftUI
import UIKit

struct FeedPager: UIViewControllerRepresentable {
    let items: [Sekai]
    let active: Bool
    let nearEnd: (String) -> Void
    let reportContent: (String) -> Void
    let blockCreator: (String) -> Void

    func makeUIViewController(context: Context) -> FeedPagerController { FeedPagerController() }
    func updateUIViewController(_ controller: FeedPagerController, context: Context) {
        controller.nearEnd = nearEnd
        controller.reportContent = reportContent
        controller.blockCreator = blockCreator
        controller.setActive(active)
        controller.setItems(items)
    }
    static func dismantleUIViewController(_ controller: FeedPagerController, coordinator: ()) {
        controller.suspend()
    }
}

@MainActor
final class FeedPagerController: UIViewController, UICollectionViewDelegate {
    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private let playback = PlaybackCoordinator()
    private let performance = FeedPerformanceProbe()
    private var items: [Sekai] = []
    private var slots: [String: WebSlot] = [:]
    private var selectedID: String?
    private var active = false
    private var visible = false
    private var scrolling = false
    private var applyingSnapshot = false
    private var snapshotRevision = 0
    private var releaseObserver: NSObjectProtocol?
    private var lastSize = CGSize.zero
    private var neighborsEnabled = true
    private var terminationRetries: Set<String> = []
    private var pendingRetries: Set<String> = []
    var nearEnd: ((String) -> Void)?
    var reportContent: ((String) -> Void)?
    var blockCreator: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collection.isPagingEnabled = true
        collection.isPrefetchingEnabled = false
        collection.showsVerticalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.backgroundColor = .black
        collection.delegate = self
        collection.register(FeedCell.self, forCellWithReuseIdentifier: FeedCell.reuseID)
        collection.frame = view.bounds
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collection)
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { [weak self] collection, path, id in
            guard let self, let item = self.items.first(where: { $0.id == id }),
                  let cell = collection.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseID, for: path) as? FeedCell else { return nil }
            self.configure(cell, item: item)
            return cell
        }
        releaseObserver = NotificationCenter.default.addObserver(forName: .feedWebViewReleased, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateWindow() }
        }
        playback.didReconcile = { [weak self] in self?.updateWindow() }
    }

    deinit {
        if let releaseObserver { NotificationCenter.default.removeObserver(releaseObserver) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        settle()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        suspend()
    }

    func suspend() {
        performance.end()
        visible = false
        playback.update(target: nil)
        updateWindow()
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if !active { playback.update(target: nil) }
        if isViewLoaded { updateWindow() }
    }

    func setItems(_ next: [Sekai]) {
        loadViewIfNeeded()
        guard items != next else { return }
        let oldIndex = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let oldItems = items
        items = next
        if !next.contains(where: { $0.id == selectedID }) {
            // Prefer the nearest surviving successor, then predecessor.
            let survivors = Set(next.map(\.id))
            selectedID = oldItems.dropFirst(oldIndex).first(where: { survivors.contains($0.id) })?.id
                ?? oldItems.prefix(oldIndex).last(where: { survivors.contains($0.id) })?.id
                ?? next.first?.id
            playback.update(target: nil)
            for case let cell as FeedCell in collection.visibleCells where !survivors.contains(cell.itemID ?? "") {
                cell.detach()
                cell.isHidden = true
            }
        }
        applyingSnapshot = true
        snapshotRevision += 1
        let revision = snapshotRevision
        playback.update(target: nil)
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(next.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, self.snapshotRevision == revision else { return }
            self.applyingSnapshot = false
            if !self.collection.isDragging && !self.collection.isDecelerating {
                self.recenter()
                self.settle()
            }
        }
        updateWindow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = collection.bounds.size
        guard size.width > 0, size.height > 0, size != lastSize else { return }
        playback.update(target: nil)
        lastSize = size
        layout.itemSize = size
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        recenter()
        if !scrolling { settle() }
    }

    private func recenter() {
        guard !applyingSnapshot, lastSize.height > 0,
              let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) else { return }
        playback.update(target: nil)
        collection.setContentOffset(CGPoint(x: 0, y: CGFloat(index) * lastSize.height), animated: false)
    }

    private var aligned: Bool {
        guard lastSize.height > 0, let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID }) else { return false }
        return abs(collection.contentOffset.y - CGFloat(index) * lastSize.height) < 1
    }

    private func settle() {
        guard !applyingSnapshot,
              lastSize.height > 0, !items.isEmpty else { return }
        let index = min(max(Int((collection.contentOffset.y / lastSize.height).rounded()), 0), items.count - 1)
        selectedID = items[index].id
        scrolling = false
        performance.end()
        if !aligned { recenter() }
        updateWindow()
        nearEnd?(items[index].id)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        performance.begin()
        scrolling = true
        neighborsEnabled = true
        playback.update(target: nil)
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settle() }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? FeedCell, let id = dataSource.itemIdentifier(for: indexPath),
              let item = items.first(where: { $0.id == id }) else { return }
        configure(cell, item: item)
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? FeedCell)?.detach()
    }

    private func configure(_ cell: FeedCell, item: Sekai) {
        cell.isHidden = false
        cell.reportContent = { [weak self] in self?.reportContent?(item.id) }
        cell.blockCreator = { [weak self] in self?.blockCreator?(item.creatorID) }
        cell.configure(item: item, slot: slots[item.id])
        cell.retry = { [weak self] in self?.retry(item.id) }
    }

    private func updateWindow() {
        guard isViewLoaded else { return }
        // A WebView started while a diffable snapshot is applying may not be in a
        // cell yet. Wait for the completion callback, which recenters the stable
        // selection and then rebuilds this window after attachment.
        guard !applyingSnapshot else {
            playback.update(target: nil)
            return
        }
        let eligible = active && visible && !scrolling && !applyingSnapshot && aligned
        let current = selectedID.flatMap { slots[$0] }
        playback.update(target: eligible && current?.ready == true ? current : nil)

        var window: [Sekai] = []
        if active && visible, let index = items.firstIndex(where: { $0.id == selectedID }) {
            window.append(items[index]) // Current always loads first.
            if neighborsEnabled {
                if index + 1 < items.count { window.append(items[index + 1]) }
                if index > 0 { window.append(items[index - 1]) }
            }
        }
        let wanted = Set(window.map(\.id))
        for (id, slot) in slots where !wanted.contains(id) && !playback.isBusy(with: slot) {
            slot.changed = nil
            slot.discard()
            slots.removeValue(forKey: id)
        }
        for id in pendingRetries {
            guard let slot = slots[id], !playback.isBusy(with: slot) else { continue }
            slot.changed = nil
            slot.discard()
            slots.removeValue(forKey: id)
            pendingRetries.remove(id)
        }
        // A pending old command still occupies a slot until shutdown completes.
        for item in window where slots[item.id] == nil && slots.count < 3 && WebViewLifetime.liveCount < 3 {
            let slot = WebSlot(item: item)
            slots[item.id] = slot
            slot.changed = { [weak self, weak slot] in
                guard let self, let slot, self.slots[item.id] === slot else { return }
                self.updateWindow()
            }
            slot.terminated = { [weak self] in
                guard let self, self.selectedID == item.id, self.active, self.visible,
                      self.terminationRetries.insert(item.id).inserted else { return }
                self.pendingRetries.insert(item.id)
                self.updateWindow()
            }
        }
        if let selectedID, slots[selectedID]?.ready != true, slots[selectedID]?.failed != true {
            for (id, slot) in slots where id != selectedID && slot.loading { slot.cancelLoad() }
        }
        for case let cell as FeedCell in collection.visibleCells {
            if let item = items.first(where: { $0.id == cell.itemID }) { configure(cell, item: item) }
        }
        // Attach the current slot before loading it. In practice, WebKit can stall
        // a navigation started while the new view still has no cell hierarchy.
        // Neighbor loads remain serialized behind that navigation.
        if !slots.values.contains(where: \.loading), let next = window.compactMap({ slots[$0.id] }).first(where: { !$0.ready && !$0.failed }) {
            next.load()
        }
        let readyCurrent = selectedID.flatMap { slots[$0] }
        playback.update(target: eligible && readyCurrent?.ready == true ? readyCurrent : nil)
    }

    private func retry(_ id: String, explicit: Bool = true) {
        guard let slot = slots[id] else { return }
        if explicit { terminationRetries.remove(id) }
        if playback.isBusy(with: slot) {
            pendingRetries.insert(id)
            playback.update(target: nil)
            return
        }
        slot.changed = nil
        slot.discard()
        slots.removeValue(forKey: id)
        updateWindow()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        neighborsEnabled = false
        updateWindow()
    }
}
