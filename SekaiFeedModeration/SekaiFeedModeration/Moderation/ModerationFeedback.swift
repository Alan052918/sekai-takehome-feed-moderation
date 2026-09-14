enum ModerationFeedback: Equatable {
    case creatorBlocked
    case contentHidden
    case deliveryFailed

    var message: String {
        switch self {
        case .creatorBlocked:
            return "Creator blocked on this device"
        case .contentHidden:
            return "Content hidden on this device"
        case .deliveryFailed:
            return "Still hidden on this device; the server request failed. It won't retry automatically."
        }
    }
}
