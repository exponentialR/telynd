import Foundation

public struct ReadinessReport: Equatable {
    public var checkedAt: Date
    public var values: [String: String]
    public init(output: String, checkedAt: Date = Date()) {
        self.checkedAt = checkedAt
        values = [:]
        for line in output.split(separator: "\n") where line.hasPrefix("TELYND:") {
            let pair = line.dropFirst(7).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 { values[String(pair[0])] = String(pair[1]) }
        }
    }
    public func accepts(exitCode: Int32, recoveryRequested: Bool) -> Bool {
        (exitCode == 0 || (recoveryRequested && [3, 4].contains(exitCode))) && values["ssh"] == "ready" && values["check"] == "complete"
    }
    public var supported: Bool { values["os"] == "linux" && values["systemd"] == "available" }
    public var recoveryEnabled: Bool { supported && values["installation"] == "verified" && values["timer"] == "active" && values["timer_enabled"] == "enabled" }
    public func isStale(at date: Date = Date()) -> Bool { date.timeIntervalSince(checkedAt) > 300 }
    public func configurationLabel(at date: Date = Date()) -> String {
        if isStale(at: date) { return "Verification is stale" }
        if values["ssh"] != "ready" { return "SSH setup needs attention" }
        if !supported { return "Connection only — recovery unsupported" }
        if values["service_loaded"] == "not-found" { return "Chrome host service not found" }
        if let missing = values["missing_tools"], !missing.isEmpty { return "Recovery tools missing: \(missing)" }
        if values["installation"] == "unsupported_root" { return "Use a desktop account for recovery" }
        if values["installation"] == "unverified" { return "Recovery permissions need verification" }
        if recoveryEnabled { return "Recovery enabled" }
        if values["installation"] == "partial" || values["installation"] == "unsafe" { return "Recovery setup needs attention" }
        return "Recovery not configured"
    }
    public var serviceLabel: String { values["service"] ?? "unknown" }
}

public enum SSHResult: Equatable {
    case ready, timedOut, authenticationRequired, identityNeedsVerification, identityChanged, unreachable, failed
    public init(code: Int32, output: String) {
        if code == -2 { self = .timedOut }
        else if output.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") { self = .identityChanged }
        else if output.contains("Host key verification failed") { self = .identityNeedsVerification }
        else if output.contains("Permission denied") { self = .authenticationRequired }
        else if output.contains("timed out") || output.contains("No route") || output.contains("Connection refused") || output.contains("Could not resolve hostname") { self = .unreachable }
        else { self = code == 0 ? .ready : .failed }
    }
    public var guidance: String {
        switch self {
        case .timedOut: return "SSH verification timed out. Check the network route and try again."
        case .ready: return "SSH access verified. Google session availability is not checked."
        case .authenticationRequired: return "SSH authorisation is needed. Use Authorise SSH access; your Linux password is entered in Terminal."
        case .identityNeedsVerification: return "Verify this host's fingerprint against a trusted record in SSH Terminal, then recheck."
        case .identityChanged: return "The host identity has changed. Stop and confirm its fingerprint through a trusted route; Telynd will not bypass this check."
        case .unreachable: return "SSH could not reach this computer. Check that it is awake and that your configured network route is available."
        case .failed: return "SSH verification did not finish successfully. Retry or use SSH Terminal for details."
        }
    }
}
