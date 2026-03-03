import Foundation

/// Training mode for personalization and federated learning.
///
/// This enum provides a clear API for choosing between:
/// - `localOnly`: Maximum privacy, all training stays on-device
/// - `federated`: Privacy-preserving collaborative learning with encrypted updates
public enum TrainingMode: String, Codable {
    /// Local-only personalization mode (maximum privacy).
    ///
    /// In this mode:
    /// - All training happens on-device
    /// - Model stays on-device
    /// - Training data never leaves device
    /// - NO updates sent to server
    /// - Best for privacy-critical applications
    /// - GDPR/CCPA/HIPAA compliant by design
    ///
    /// **Use cases:**
    /// - Healthcare applications with PHI
    /// - Financial applications with PII
    /// - Apps requiring maximum privacy
    /// - Testing and development
    case localOnly = "local_only"

    /// Federated learning mode (privacy + collective intelligence).
    ///
    /// In this mode:
    /// - Training happens on-device
    /// - Model personalizes locally
    /// - Training data stays on-device
    /// - Only encrypted weight deltas sent to server
    /// - Cannot reconstruct original data from deltas
    /// - Benefits from global model improvements
    ///
    /// **Use cases:**
    /// - Keyboard predictions
    /// - Content recommendations
    /// - Search suggestions
    /// - Apps with millions of users
    /// - When users opt-in to sharing
    case federated

    /// Whether this mode uploads updates to the server.
    public var uploadsToServer: Bool {
        switch self {
        case .localOnly:
            return false
        case .federated:
            return true
        }
    }

    /// User-friendly description of what this mode does.
    public var description: String {
        switch self {
        case .localOnly:
            return "Your model learns your patterns. Data never leaves your device."
        case .federated:
            return "Your model learns from millions while keeping your data private."
        }
    }

    /// Privacy level indicator.
    public var privacyLevel: String {
        switch self {
        case .localOnly:
            return "Maximum"
        case .federated:
            return "High"
        }
    }

    /// Data transmission indicator for UI display.
    public var dataTransmitted: String {
        switch self {
        case .localOnly:
            return "0 bytes"
        case .federated:
            return "Encrypted weight deltas only"
        }
    }
}
