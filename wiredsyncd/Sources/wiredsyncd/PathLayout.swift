import Foundation
final class PathLayout {
    static let appSupportDirEnv = "WIREDSYNCD_APP_SUPPORT_DIR"
    static let runDirEnv = "WIREDSYNCD_RUN_DIR"

    let baseDir: URL
    let configPath: URL
    let statePath: URL
    let runDir: URL
    let socketPath: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultBaseDir = home.appendingPathComponent("Library/Application Support/WiredSync", isDirectory: true)
        self.baseDir = environment[Self.appSupportDirEnv].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        } ?? defaultBaseDir
        self.configPath = baseDir.appendingPathComponent("config.json", isDirectory: false)
        self.statePath = baseDir.appendingPathComponent("state.sqlite", isDirectory: false)
        self.runDir = environment[Self.runDirEnv].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        } ?? baseDir.appendingPathComponent("run", isDirectory: true)
        self.socketPath = runDir.appendingPathComponent("wiredsyncd.sock", isDirectory: false)
    }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
    }
}
