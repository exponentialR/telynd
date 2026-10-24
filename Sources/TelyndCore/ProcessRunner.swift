import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ProcessRunner {
    /// Bound both execution time and output. Never accept partial protocol output on failure.
    public static func run(_ command: String, arguments: [String], input: URL? = nil, timeout: TimeInterval = 40, outputLimit: Int = 65_536) -> (code: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        var inputFile: FileHandle?
        defer { try? inputFile?.close(); try? pipe.fileHandleForReading.close() }
        do {
            if let input { inputFile = try FileHandle(forReadingFrom: input) }
            process.executableURL = URL(fileURLWithPath: command); process.arguments = arguments
            process.standardInput = inputFile ?? FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = pipe
            let fd = pipe.fileHandleForReading.fileDescriptor
            guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { return (-1, "Verification could not be started.") }
            try process.run()
            try? pipe.fileHandleForWriting.close()
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            var forced: Int32?
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    if data.count + count > outputLimit { forced = -3; break }
                    data.append(contentsOf: buffer.prefix(count))
                } else {
                    if !process.isRunning { break }
                    if count == -1 && errno != EAGAIN && errno != EINTR { forced = -1; break }
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if ProcessInfo.processInfo.systemUptime >= deadline { forced = -2; break }
            }
            if forced != nil && process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            if let forced { return (forced, forced == -2 ? "SSH verification timed out." : "Verification output could not be accepted.") }
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch { return (-1, "Verification could not be started.") }
    }
}
