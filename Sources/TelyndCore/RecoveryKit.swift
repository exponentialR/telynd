import Foundation

public enum RecoveryKit {
    public static func files(for platform: HostPlatform) -> [String] {
        switch platform {
        case .macos: return ["macos-recovery.sh"]
        case .windows: return ["windows-recovery.ps1", "WindowsServicePolicy.cs"]
        default: return []
        }
    }
    public static func instructions(for desktop: Desktop) -> String {
        let id = desktop.id.uuidString
        let command = desktop.hostPlatform == .macos ? "/bin/bash ./macos-recovery.sh" : ".\\windows-recovery.ps1"
        let argument = desktop.hostPlatform == .macos ? "\(id)" : "-DesktopID \(id)"
        let action = desktop.hostPlatform == .macos ? "" : "-Action "
        return """
        Telynd recovery kit — \(desktop.hostPlatform.label)
        Computer ID: \(id)

        Development preview. These scripts are not signed public installers.
        Review the source and transfer this entire folder to the intended host.
        Do not run a kit from an untrusted source. Do not disable OS security
        protections if the OS blocks it; use the reviewed source workflow or
        wait for a signed distribution. No passwords are saved by Telynd.

        First connect successfully with Google Chrome Remote Desktop.
        Open Terminal (Mac) or PowerShell (Windows) in this folder.
        On Windows, setup/disable/uninstall/manual recovery need an elevated
        administrator PowerShell; check is read-only. No inbound SSH is needed.
        On Mac, use the signed-in desktop account WITHOUT sudo. Grant Google's
        screen/control permissions through System Settings when required.

        Check and export a snapshot:
          \(command) \(action)check \(argument) > report.json
        Explicitly enable Telynd recovery:
          \(command) \(action)install \(argument) > report.json
        Disable Telynd recovery (Windows restores its original failure policy):
          \(command) \(action)disable \(argument) > report.json
        Remove owned recovery configuration:
          \(command) \(action)uninstall \(argument) > report.json
        Explicit manual recovery if stopped:
          \(command) \(action)recover \(argument) > report.json

        Bring report.json back to this Mac and import it into this computer's
        recovery settings. Reports are user-supplied snapshots, not authenticated
        live checks. They become stale after five minutes and reset on relaunch.

        Mac recovery: signed-in Aqua desktop session only; checks every two
        minutes, at most three start attempts per 30 minutes. Google remote
        access must remain explicitly enabled. Missing privacy permissions,
        logout, power/network failures and expired Google authorisation can
        still prevent connection. Native descriptor locking is required; older
        Mac implementations are refused before installation. Native locks release
        after interruption; keep operation.lock in place. A legacy directory
        named lock requires review and must not be removed during an action.
        A changed kit requires verified uninstall of the old revision first.

        Windows recovery: native service CRASH recovery only, two restart
        attempts with 60/120-second delays, then no action until its one-day
        failure-count reset. An orderly stop is NOT automatically recovered.
        Manual recovery requires Automatic start mode. Google uses Manual to
        deliberately stop its host; Manual and Disabled modes stay stopped.
        No background Telynd agent, scheduled task or network listener is added.
        Existing third-party failure actions are recorded and restored only if
        they still match recognised original/Telynd policy. No host restart.

        An active service is not proof of a Google session. Confirm connection
        in Chrome separately. Keep report.json private; it contains the computer
        ID and system information. \(desktop.hostPlatform == .windows ? "Windows UTF-16 report files are accepted by the Mac importer." : "")
        """
    }
}
