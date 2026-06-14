import Foundation

/// Runs shell commands via /bin/zsh -c. Captures stdout/stderr.
/// If `waitForExit` is false, returns immediately after spawning the process.
public struct ShellResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let didTimeout: Bool
}

public enum ShellRunner {
    /// Executes `command` and returns the result. If `waitForExit` is false,
    /// returns immediately with exit code -1 and empty output.
    /// `timeout` (seconds) terminates the process if exceeded.
    public static func run(command: String, waitForExit: Bool, timeout: TimeInterval = 10.0) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: "Failed to start: \(error)", didTimeout: false)
        }

        guard waitForExit else {
            return ShellResult(exitCode: -1, stdout: "", stderr: "", didTimeout: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var didTimeout = false
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                didTimeout = true
                break
            }
            // 50ms poll; cheap and bounded.
            Thread.sleep(forTimeInterval: 0.05)
        }
        // If still alive after terminate(), wait briefly.
        process.waitUntilExit()

        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            didTimeout: didTimeout
        )
    }
}
