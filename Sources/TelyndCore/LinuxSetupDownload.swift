import Foundation
import CryptoKit

/// The public preview download is pinned to the exact bundled helper, not a
/// mutable branch or "latest" asset. Update this pin after committing a new deb.
public enum LinuxSetupDownload {
    public static let filename = "telynd-setup_0.2.1_all.deb"
    public static let revision = "cf0da4ac8be8e6fcc83de43e64a64c0ebd2be645"
    private static let digest = "62d75d19860a6c304e0d35c631b8738b6d330ebd3f082cb7a1a7f78dae17db54"
    public static var url: URL {
        URL(string: "https://raw.githubusercontent.com/exponentialR/telynd/\(revision)/assets/\(filename)")!
    }
    public static func verifiedURL(for bundledHelper: Data) -> URL? {
        let actual = SHA256.hash(data: bundledHelper).map { String(format: "%02x", $0) }.joined()
        return actual == digest ? url : nil
    }
}
