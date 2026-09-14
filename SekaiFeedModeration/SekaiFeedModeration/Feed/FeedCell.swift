import UIKit
import WebKit

final class FeedCell: UICollectionViewCell {
    static let reuseID = "FeedCell"
    private let container = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let moderationButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    var retry: (() -> Void)?
    var reportContent: (() -> Void)?
    var blockCreator: (() -> Void)?
    private(set) var itemID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        [container, titleLabel, statusLabel, retryButton, moderationButton, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 2
        titleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        statusLabel.textColor = .lightGray
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        retryButton.setTitle("Retry content", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        moderationButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moderationButton.tintColor = .white
        moderationButton.showsMenuAsPrimaryAction = true
        moderationButton.accessibilityLabel = "Moderation actions"
        spinner.color = .white
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            moderationButton.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 16),
            moderationButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -40),
            retryButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            retryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: Sekai, slot: WebSlot?) {
        itemID = item.id
        moderationButton.menu = UIMenu(children: [
            UIAction(title: "Report as spam", image: UIImage(systemName: "exclamationmark.bubble")) { [weak self] _ in
                self?.reportContent?()
            },
            UIAction(title: "Block creator", image: UIImage(systemName: "hand.raised"), attributes: .destructive) { [weak self] _ in
                self?.blockCreator?()
            }
        ])
        titleLabel.text = "\(item.title)\n@\(item.creatorName) · ♥ \(item.likeCount)"
        let webView = slot?.webView
        for view in container.subviews where view !== webView { view.removeFromSuperview() }
        if let webView, webView.superview !== container {
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(webView)
        }
        // UICollectionView mounts a configured cell after the data source
        // callback returns. Starting after that mount avoids a zero-hierarchy
        // WebKit navigation while preserving pager-owned WebView ownership.
        DispatchQueue.main.async { [weak slot] in slot?.load() }
        statusLabel.text = slot?.failed == true ? "This sekai couldn't load." : "Loading sekai…"
        statusLabel.isHidden = slot?.ready == true
        retryButton.isHidden = slot?.failed != true
        if slot?.ready == true || slot?.failed == true { spinner.stopAnimating() }
        else { spinner.startAnimating() }
    }

    func detach() { container.subviews.forEach { $0.removeFromSuperview() } }
    override func prepareForReuse() {
        super.prepareForReuse()
        detach()
        itemID = nil
        retry = nil
        reportContent = nil
        blockCreator = nil
    }
    @objc private func retryTapped() { retry?() }
}
