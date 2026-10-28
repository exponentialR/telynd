import Foundation
import CryptoKit

/// The public preview download is pinned to the exact bundled helper, not a
/// mutable branch or "latest" asset. Update this pin after committing a new deb.
public enum LinuxSetupDownload {
    public static let filename = "telynd-setup_0.2.2_all.deb"
    public static let revision = "5eccc834f7092b2b87aad4194987de8aa207bd6d"
    private static let digest = "6264d354f2cdb6f94bf38abcf59b530251118ed86199e74b6c2f1186463b179c"
    public static var url: URL {
        URL(string: "https://raw.githubusercontent.com/exponentialR/telynd/\(revision)/assets/\(filename)")!
    }
    public static func verifiedURL(for bundledHelper: Data) -> URL? {
        let actual = SHA256.hash(data: bundledHelper).map { String(format: "%02x", $0) }.joined()
        return actual == digest ? url : nil
    }
    /// A separate clipboard action for a Linux terminal, with checksum verification
    /// before apt runs. The subshell keeps its directory and error mode local.
    public static func verifiedInstallCommand(for bundledHelper: Data) -> String? {
        guard let url = verifiedURL(for: bundledHelper) else { return nil }
        return """
        (
          set -e
          cd "$(mktemp -d)"
          wget --https-only -O '\(filename)' '\(url.absoluteString)'
          printf '%s\\n' '\(digest)  \(filename)' | sha256sum --check -
          sudo apt install './\(filename)'
          telynd-setup
        )
        """
    }
}
