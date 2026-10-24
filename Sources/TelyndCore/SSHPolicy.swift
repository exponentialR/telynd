import Foundation

public enum SSHPolicy {
    /// Explicitly override unsafe user defaults while retaining hostname/routing configuration.
    public static func readinessArguments(identity: String, target: String, command: String) -> [String] {
        let options = ["BatchMode=yes", "StrictHostKeyChecking=yes", "ForwardAgent=no", "ForwardX11=no", "ForwardX11Trusted=no", "ClearAllForwardings=yes", "PermitLocalCommand=no", "ControlMaster=no", "ControlPath=none", "ControlPersist=no", "ForkAfterAuthentication=no", "ConnectTimeout=8", "ServerAliveInterval=5", "ServerAliveCountMax=2", "IgnoreUnknown=UseKeychain", "UseKeychain=yes", "IdentitiesOnly=yes", "AddKeysToAgent=yes", "IdentityFile=\(identity)"]
        return ["-T"] + options.flatMap { ["-o", $0] } + [target, command]
    }
}
