import Foundation

public enum ChromeCaptureError: LocalizedError {
    case chromeClosed, permissionDenied, unavailable, notConnection
    public var errorDescription: String? {
        switch self {
        case .chromeClosed: return "Open your computer in Chrome Remote Desktop first, then choose Use open computer."
        case .permissionDenied: return "Allow Telynd to interact with Google Chrome in System Settings → Privacy & Security → Automation, then try again. You can also enter the link manually."
        case .unavailable: return "Chrome’s open tab could not be read. Try again, or enter the link manually."
        case .notConnection: return "Open the individual computer in Chrome Remote Desktop first. Its device list and other pages cannot be saved as a connection."
        }
    }
}

public enum ChromeConnectionCapture {
    /// Browser input is untrusted data. Never evaluate it or accept arbitrary links.
    public static func validatedLink(_ address: String?) throws -> String {
        guard let address, address.utf8.count <= 2048 else { throw ChromeCaptureError.unavailable }
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard InputValidation.directChromeURL(value) else { throw ChromeCaptureError.notConnection }
        return value
    }
}

/// Owned by one editor. A result belongs to its original request and draft.
public struct ChromeCaptureRequests {
    private var pending: (id: UUID, desktop: Desktop)?
    public init() {}
    public mutating func begin(for desktop: Desktop) -> UUID {
        let id = UUID()
        pending = (id, desktop)
        return id
    }
    public mutating func invalidate() { pending = nil }
    public mutating func consume(_ id: UUID, current: Desktop) -> Bool {
        guard let pending, pending.id == id else { return false }
        self.pending = nil
        return pending.desktop == current
    }
}
