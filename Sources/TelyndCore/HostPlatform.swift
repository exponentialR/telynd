import Foundation

public enum HostPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, linux, macos, windows
    public var id: String { rawValue }
    public var label: String {
        switch self { case .unknown: return "Not selected"; case .linux: return "Linux"; case .macos: return "Mac"; case .windows: return "Windows" }
    }
    /// Old SSH desktops retain Linux discovery; selection never proves the remote OS.
    public var usesSSHRecovery: Bool { self == .linux || self == .unknown }
}

public enum HostReportError: LocalizedError {
    case invalid, mismatch, future
    public var errorDescription: String? {
        switch self {
        case .invalid: return "This is not a complete supported Telynd host report. Export a new report on the remote computer."
        case .mismatch: return "This report is for a different computer or operating system. Check the selected computer and recovery kit."
        case .future: return "The report time is in the future. Correct the host clock and export again."
        }
    }
}

/// Host-exported evidence is data, never a source of commands, paths or privileges.
/// Reports are user-supplied snapshots, not authenticated live observations.
public struct LocalHostReport: Codable, Equatable {
    public let schemaVersion: Int
    public let desktopID: UUID
    public let platform: HostPlatform
    public let osVersion: String
    public let architecture: String
    public let checkedAt: Double
    public let service: String
    public let enablement: String
    public let installation: String
    public let recovery: String
    public let permissions: String
    public let outcome: String

    public static func parse(_ data: Data, desktop: Desktop, now: Date = Date()) throws -> LocalHostReport {
        guard data.count <= 16384, let report = try? JSONDecoder().decode(Self.self, from: data), report.schemaVersion == 1,
              [.macos, .windows].contains(report.platform), report.checkedAt.isFinite, report.checkedAt > 0,
              [report.osVersion, report.architecture].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }),
              ["running", "stopped", "transitioning", "missing", "unknown"].contains(report.service),
              ["enabled", "disabled", "unknown"].contains(report.enablement),
              ["verified", "missing", "disabled", "drift", "partial", "unknown"].contains(report.installation),
              ["stopped-service", "crash-only", "unavailable"].contains(report.recovery),
              ["unknown", "needs-attention"].contains(report.permissions),
              ["checked", "installed", "disabled", "uninstalled", "started", "unchanged", "retry-limit"].contains(report.outcome) else { throw HostReportError.invalid }
        guard report.desktopID == desktop.id, report.platform == desktop.hostPlatform else { throw HostReportError.mismatch }
        guard report.checkedAt <= now.timeIntervalSince1970 + 60 else { throw HostReportError.future }
        return report
    }
    public var readiness: ReadinessReport {
        var report = ReadinessReport(output: "", checkedAt: Date(timeIntervalSince1970: checkedAt))
        report.values = ["protocol": "1", "origin": "import", "os": platform.rawValue, "os_version": osVersion, "architecture": architecture,
                         "service": service, "chrome_enabled": enablement, "installation": installation,
                         "recovery_scope": recovery, "permissions": permissions, "outcome": outcome, "check": "complete"]
        return report
    }
}
