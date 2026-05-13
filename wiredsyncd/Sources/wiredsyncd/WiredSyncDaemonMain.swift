import Foundation
import Darwin

@main
struct WiredSyncDaemonMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        redirectOutputToLogFiles()
        do {
            try runServer()
        } catch {
            fputs("wiredsyncd: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // Redirect stdout/stderr to log files so logging works regardless of
    // how launchd loaded us (SMAppService plists don't expand ~ in log paths).
    private static func redirectOutputToLogFiles() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WiredSync")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let outPath = logDir.appendingPathComponent("wiredsyncd.out.log").path
        let errPath = logDir.appendingPathComponent("wiredsyncd.err.log").path
        freopen(outPath, "a", stdout)
        freopen(errPath, "a", stderr)
    }
}
