import Foundation

public enum SSHPolicy {
    /// Interactive login uses a real PTY and asks before trusting an unknown host.
    /// Arguments go directly to ssh; no local shell interprets saved settings.
    public static func interactiveArguments(identity: String, target: String) -> [String] {
        let options = ["BatchMode=no", "StrictHostKeyChecking=ask", "ForwardAgent=no", "ForwardX11=no", "ForwardX11Trusted=no", "ClearAllForwardings=yes", "PermitLocalCommand=no", "ControlMaster=no", "ControlPath=none", "ControlPersist=no", "ForkAfterAuthentication=no", "ConnectTimeout=10", "ServerAliveInterval=15", "ServerAliveCountMax=3", "IgnoreUnknown=UseKeychain", "UseKeychain=yes", "IdentitiesOnly=yes", "AddKeysToAgent=yes"]
        return ["-tt"] + options.flatMap { ["-o", $0] } + ["-i", identity, target]
    }

    /// Explicitly override unsafe user defaults while retaining hostname/routing configuration.
    public static func readinessArguments(identity: String, target: String, command: String) -> [String] {
        // -o values use SSH configuration syntax, even in a single argv item.
        let quotedIdentity = "\"" + identity.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        let options = ["BatchMode=yes", "StrictHostKeyChecking=yes", "ForwardAgent=no", "ForwardX11=no", "ForwardX11Trusted=no", "ClearAllForwardings=yes", "PermitLocalCommand=no", "ControlMaster=no", "ControlPath=none", "ControlPersist=no", "ForkAfterAuthentication=no", "ConnectTimeout=8", "ServerAliveInterval=5", "ServerAliveCountMax=2", "IgnoreUnknown=UseKeychain", "UseKeychain=yes", "IdentitiesOnly=yes", "AddKeysToAgent=yes", "IdentityFile=\(quotedIdentity)"]
        return ["-T"] + options.flatMap { ["-o", $0] } + [target, command]
    }
}
