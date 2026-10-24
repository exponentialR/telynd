import Foundation

public struct HostObservation {
    public var busy: Bool
    public var checkedAt: Date?
    public var ssh: SSHResult?
    public var report: ReadinessReport?
    public var note: String

    public init(busy: Bool = false, checkedAt: Date? = nil, ssh: SSHResult? = nil, report: ReadinessReport? = nil, note: String = "Not checked. Google session availability is unknown.") {
        self.busy = busy; self.checkedAt = checkedAt; self.ssh = ssh
        self.report = report; self.note = note
    }
}

/// Owned by the main actor in the app. Completions can change only their own request.
public struct HostChecks {
    public private(set) var observations: [UUID: HostObservation] = [:]
    private var requests: [UUID: UUID] = [:]

    public init() {}

    public mutating func begin(_ desktopID: UUID, recovering: Bool) -> UUID? {
        guard requests[desktopID] == nil else { return nil }
        let request = UUID()
        requests[desktopID] = request
        observations[desktopID] = HostObservation(busy: true, note: recovering ? "Checking whether recovery is needed…" : "Checking readiness without changing the host…")
        return request
    }

    public mutating func invalidate(_ desktopID: UUID) {
        requests[desktopID] = nil
        observations[desktopID] = nil
    }

    public mutating func complete(_ desktopID: UUID, request: UUID, observation: HostObservation?) {
        guard requests[desktopID] == request else { return }
        requests[desktopID] = nil
        observations[desktopID] = observation
    }
}
