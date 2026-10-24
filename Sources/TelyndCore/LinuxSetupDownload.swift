import Foundation
import CryptoKit

/// The public preview download is pinned to the exact bundled helper, not a
/// mutable branch or "latest" asset. Update this pin after committing a new deb.
public enum LinuxSetupDownload {
    public static let filename = "telynd-setup_0.2.1_all.deb"
    public static let revision = "be2cec8aaa5fe4593ff2d7554a294074849610fc"
    private static let digest = "7b9c53045dad44efd1707411f343710a011071545950dc58e40c134a32e5bbf4"
    public static var url: URL {
        URL(string: "https://raw.githubusercontent.com/exponentialR/telynd/\(revision)/assets/\(filename)")!
    }
    public static func verifiedURL(for bundledHelper: Data) -> URL? {
        let actual = SHA256.hash(data: bundledHelper).map { String(format: "%02x", $0) }.joined()
        return actual == digest ? url : nil
    }
}
