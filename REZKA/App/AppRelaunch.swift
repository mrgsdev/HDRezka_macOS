import AppKit

/// Quits and opens the app again: after an update, or for a new interface language.
enum AppRelaunch {
    /// Opens `app` once this process is gone; opened earlier, macOS would just bring the running
    /// copy forward. `-n` starts this copy even if another one with the same bundle ID is running,
    /// e.g. a build from Xcode.
    @MainActor
    static func relaunch(_ app: URL = Bundle.main.bundleURL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$0\"", app.path]
        try process.run()
        NSApp.terminate(nil)
    }
}
