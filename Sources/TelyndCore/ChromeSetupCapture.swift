import Foundation

public struct ChromeSetupTab: Equatable, Sendable {
    public let windowID: String
    public let tabID: String
    public init(windowID: String, tabID: String) { self.windowID = windowID; self.tabID = tabID }
    public var valid: Bool {
        [windowID, tabID].allSatisfy { !$0.isEmpty && $0.count <= 20 && $0.utf8.allSatisfy { (48...57).contains($0) } }
    }
}

public enum ChromeSetupRead: Equatable, Sendable {
    case bind(marker: String)
    case tab(ChromeSetupTab)
}

public struct ChromeSetupSnapshot: Sendable {
    public let tab: ChromeSetupTab
    public let address: String
    public init(tab: ChromeSetupTab, address: String) { self.tab = tab; self.address = address }
}

/// One explicit setup attempt, bound to its draft and the tab it opened.
/// Detection never changes a draft: the user must confirm the candidate first.
public struct ChromeSetupCapture {
    public let id = UUID()
    private let desktop: Desktop
    private let deadline: Date
    private let markerPage: URL
    private var tab: ChromeSetupTab?
    public private(set) var candidate: String?
    public var bootstrapURL: String { markerPage.absoluteString + "#telynd-\(id.uuidString)" }
    public var request: ChromeSetupRead { tab.map(ChromeSetupRead.tab) ?? .bind(marker: bootstrapURL) }
    public init(desktop: Desktop, markerPage: URL, now: Date = Date()) {
        self.desktop = desktop; self.markerPage = markerPage; deadline = now.addingTimeInterval(300)
    }
    public func isCurrent(_ current: Desktop, now: Date = Date()) -> Bool {
        // Stop polling at the deadline, but retain a detected link for review.
        current == desktop && (candidate != nil || now < deadline)
    }
    @discardableResult public mutating func receive(_ snapshot: ChromeSetupSnapshot?, for request: ChromeSetupRead, current: Desktop, now: Date = Date()) -> Bool {
        guard isCurrent(current, now: now), candidate == nil, self.request == request,
              let snapshot, snapshot.tab.valid else { return false }
        switch request {
        case .bind(let marker):
            guard snapshot.address == marker else { return false }
            tab = snapshot.tab
        case .tab(let expected):
            guard snapshot.tab == expected,
                  let link = try? ChromeConnectionCapture.validatedLink(snapshot.address) else { return false }
            candidate = link
        }
        return true
    }
    public func confirmedLink(current: Desktop, now: Date = Date()) -> String? {
        isCurrent(current, now: now) ? candidate : nil
    }
}
