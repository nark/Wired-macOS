import Foundation
import WiredSwift
#if os(macOS)
import Darwin
import SQLite3
#endif

func normalizeSyncRemotePath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty { return "/" }
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    if !normalized.hasPrefix("/") {
        normalized = "/" + normalized
    }
    return normalized
}

struct SyncActivationNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum SyncPairStatusDisplay: Equatable {
    case hidden
    case checking
    case paused
    case connecting
    case connected
    case syncing
    case reconnecting
    case error(message: String?)
    case inactive
}

enum SyncPairLocalOverride: Equatable {
    case checking(active: Bool)
    case sticky(active: Bool, until: Date)
}

struct WiredSyncPairDescriptor: Hashable {
    enum RuntimeState: String, Hashable {
        case disconnected
        case connecting
        case connected
        case syncing
        case reconnecting
        case error
        case paused
    }

    let remotePath: String
    let serverURL: String
    let login: String
    let mode: String
    let deleteRemoteEnabled: Bool
    let paused: Bool
    let runtimeState: RuntimeState?
    let runtimeLastError: String?
    let runtimeRetryCount: Int
    let runtimeNextRetryAt: String?
    let runtimeLastConnectedAt: String?
    let runtimeLastSyncStartedAt: String?
    let runtimeLastSyncCompletedAt: String?
}

enum WiredSyncDaemonIPC {
    static let defaultRPCTimeoutSeconds: Int = 8
    static let baseSupportPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
        .appendingPathComponent("Library/Application Support/WiredSync")
    static let runPath = (baseSupportPath as NSString).appendingPathComponent("run")
    static let socketPath = (runPath as NSString).appendingPathComponent("wiredsyncd.sock")
    static let configPath = (baseSupportPath as NSString).appendingPathComponent("config.json")
    static let statePath = (baseSupportPath as NSString).appendingPathComponent("state.sqlite")
    static let daemonInstallPath = (baseSupportPath as NSString).appendingPathComponent("daemon")
    static let daemonResourcesPath = (daemonInstallPath as NSString).appendingPathComponent("Resources")
    static let installedDaemonPath = (daemonInstallPath as NSString).appendingPathComponent("wiredsyncd")
    static let launchAgentLabel = "fr.read-write.wiredsyncd"

    private static var wiredSyncApplicationVersion: String? {
        WiredApplicationInfo.current().version
    }

    private static var wiredSyncApplicationBuild: String? {
        WiredApplicationInfo.current().build
    }

    static let launchAgentPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
        .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")

    static let expectedDaemonVersion = "29"

    static func addPair(
        remotePath: String,
        localPath: String,
        mode: String = "bidirectional",
        deleteRemoteEnabled: Bool = false,
        excludePatterns: String = "",
        serverURL: String,
        login: String,
        password: String
    ) throws -> String? {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "add_pair",
            "params": [
                "remote_path": remotePath,
                "local_path": localPath,
                "mode": mode,
                "delete_remote_enabled": deleteRemoteEnabled ? "true" : "false",
                "exclude_patterns": excludePatterns,
                "server_url": serverURL,
                "login": login,
                "password": password
            ]
        ]
        let response = try sendRequest(request)
        let result = response["result"] as? [String: Any]
        return result?["pair_id"] as? String
    }

    static func syncNow(remotePath: String, serverURL: String? = nil, login: String? = nil) throws -> (matched: Int, launched: Int) {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "sync_now",
            "params": [
                "remote_path": remotePath,
                "server_url": serverURL ?? "",
                "login": login ?? ""
            ]
        ]
        let response = try sendRequest(request)
        let result = response["result"] as? [String: Any]
        let matched = result?["matched"] as? Int ?? 0
        let launched = result?["launched"] as? Int ?? 0
        return (matched, launched)
    }

    static func removePairForRemote(remotePath: String, serverURL: String, login: String? = nil) throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "remove_pair_for_remote",
            "params": [
                "remote_path": remotePath,
                "server_url": serverURL,
                "login": login ?? ""
            ]
        ]
        _ = try sendRequest(request)
    }

    static func listPairedDescriptors(serverURL: String? = nil, login: String? = nil) throws -> Set<WiredSyncPairDescriptor> {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "list_pairs"
        ]
        let response = try sendRequest(request)
        guard let result = response["result"] as? [String: Any],
              let pairs = result["pairs"] as? [[String: Any]] else {
            return []
        }

        let normalizedServer = serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptors: [WiredSyncPairDescriptor] = pairs.compactMap { pair in
            guard let remotePath = pair["remote_path"] as? String else { return nil }
            if let normalizedServer, !normalizedServer.isEmpty {
                guard let pairServer = pair["server_url"] as? String, pairServer == normalizedServer else { return nil }
            }
            if let normalizedLogin, !normalizedLogin.isEmpty {
                let pairLogin = (pair["login"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard pairLogin == normalizedLogin else { return nil }
            }
            let pairServer = (pair["server_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pairLogin = (pair["login"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pausedRaw = (pair["paused"] as? String)?.lowercased() ?? "false"
            let paused = pausedRaw == "true" || pausedRaw == "1"
            let deleteRemoteRaw = (pair["delete_remote_enabled"] as? String)?.lowercased() ?? "false"
            let deleteRemoteEnabled = deleteRemoteRaw == "true" || deleteRemoteRaw == "1"
            let runtimeState = (pair["runtime_state"] as? String).flatMap(WiredSyncPairDescriptor.RuntimeState.init(rawValue:))
            return WiredSyncPairDescriptor(
                remotePath: normalizeSyncRemotePath(remotePath),
                serverURL: pairServer,
                login: pairLogin,
                mode: (pair["mode"] as? String) ?? "bidirectional",
                deleteRemoteEnabled: deleteRemoteEnabled,
                paused: paused,
                runtimeState: runtimeState,
                runtimeLastError: pair["runtime_last_error"] as? String,
                runtimeRetryCount: pair["runtime_retry_count"] as? Int ?? 0,
                runtimeNextRetryAt: pair["runtime_next_retry_at"] as? String,
                runtimeLastConnectedAt: pair["runtime_last_connected_at"] as? String,
                runtimeLastSyncStartedAt: pair["runtime_last_sync_started_at"] as? String,
                runtimeLastSyncCompletedAt: pair["runtime_last_sync_completed_at"] as? String
            )
        }
        return Set(descriptors)
    }

    @discardableResult
    static func renamePairForRemote(
        oldPath: String,
        newPath: String,
        serverURL: String,
        login: String
    ) throws -> Int {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "rename_pair_remote",
            "params": [
                "old_remote_path": oldPath,
                "new_remote_path": newPath,
                "server_url": serverURL,
                "login": login
            ]
        ]
        let response = try sendRequest(request)
        let result = response["result"] as? [String: Any]
        return result?["updated_count"] as? Int ?? 0
    }

    static func updatePairPolicy(
        remotePath: String,
        mode: String,
        deleteRemoteEnabled: Bool,
        excludePatterns: String = "",
        serverURL: String,
        login: String
    ) throws -> Int {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "update_pair_policy",
            "params": [
                "remote_path": remotePath,
                "mode": mode,
                "delete_remote_enabled": deleteRemoteEnabled ? "true" : "false",
                "exclude_patterns": excludePatterns,
                "server_url": serverURL,
                "login": login
            ]
        ]
        let response = try sendRequest(request)
        let result = response["result"] as? [String: Any]
        return result?["updated_count"] as? Int ?? 0
    }

    static func listPairedRemotePaths(serverURL: String? = nil, login: String? = nil) throws -> Set<String> {
        let descriptors = try listPairedDescriptors(serverURL: serverURL, login: login)
        return Set(descriptors.filter { !$0.paused }.map(\.remotePath))
    }

    static func configuredPairedRemotePaths(serverURL: String? = nil, login: String? = nil) -> Set<String> {
        struct ConfigFile: Decodable {
            struct Pair: Decodable {
                struct Endpoint: Decodable {
                    let serverURL: String
                    let login: String?

                    enum CodingKeys: String, CodingKey {
                        case serverURL
                        case login
                    }
                }

                let remotePath: String
                let endpoint: Endpoint
                let paused: Bool?

                enum CodingKeys: String, CodingKey {
                    case remotePath
                    case endpoint
                    case paused
                }
            }

            let pairs: [Pair]
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: data) else {
            return []
        }

        let normalizedServer = serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = config.pairs.compactMap { pair -> String? in
            if pair.paused == true {
                return nil
            }
            if let normalizedServer, !normalizedServer.isEmpty,
               pair.endpoint.serverURL != normalizedServer {
                return nil
            }
            if let normalizedLogin, !normalizedLogin.isEmpty {
                let pairLogin = pair.endpoint.login?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if pairLogin != normalizedLogin {
                    return nil
                }
            }
            return normalizeSyncRemotePath(pair.remotePath)
        }
        return Set(paths)
    }

    static func stateDatabasePairedRemotePaths(serverURL: String? = nil, login: String? = nil) -> Set<String> {
        var database: OpaquePointer?
        guard sqlite3_open_v2(statePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT remote_path, endpoint_json FROM sync_pairs WHERE paused = 0;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }

        let normalizedServer = serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsEndpointFiltering = (normalizedServer?.isEmpty == false) || (normalizedLogin?.isEmpty == false)
        var paths: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let remotePath = String(cString: raw)
            if needsEndpointFiltering {
                let endpointJSON: String
                if let endpointRaw = sqlite3_column_text(statement, 1) {
                    endpointJSON = String(cString: endpointRaw)
                } else {
                    endpointJSON = ""
                }
                let endpointData = Data(endpointJSON.utf8)
                let endpointObject = (try? JSONSerialization.jsonObject(with: endpointData)) as? [String: Any]
                let pairServer = (endpointObject?["serverURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pairLogin = (endpointObject?["login"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let normalizedServer, !normalizedServer.isEmpty, pairServer != normalizedServer {
                    continue
                }
                if let normalizedLogin, !normalizedLogin.isEmpty, pairLogin != normalizedLogin {
                    continue
                }
            }
            paths.insert(normalizeSyncRemotePath(remotePath))
        }
        return paths
    }

    static func persistedPairedRemotePaths(serverURL: String? = nil, login: String? = nil) -> Set<String> {
        configuredPairedRemotePaths(serverURL: serverURL, login: login).union(
            stateDatabasePairedRemotePaths(serverURL: serverURL, login: login)
        )
    }

    @discardableResult
    private static func sendRequest(_ request: [String: Any]) throws -> [String: Any] {
        let method = request["method"] as? String
        let timeoutSeconds = timeoutSecondsForMethod(method)
        do {
            return try performRequest(request, timeoutSeconds: timeoutSeconds)
        } catch {
            guard shouldAttemptLaunchAgentRecovery(after: error) else {
                throw error
            }
            try installAndStartLaunchAgent()
            return try performRequest(request, timeoutSeconds: timeoutSeconds)
        }
    }

    private static func shouldAttemptLaunchAgentRecovery(after error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "wiredsyncd.ipc" else { return false }
        if nsError.code == 1 || nsError.code == 2 { return true }
        if nsError.code == 6,
           let msg = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
           msg == "method not found" { return true }
        return false
    }

    private static func timeoutSecondsForMethod(_ method: String?) -> Int {
        switch method {
        case "status", "list_pairs":
            return 3
        case "logs_tail":
            return 4
        case "add_pair", "remove_pair", "remove_pair_for_remote", "rename_pair_remote", "pause_pair", "resume_pair", "sync_now":
            return 8
        default:
            return defaultRPCTimeoutSeconds
        }
    }

    private static func performRequest(_ request: [String: Any], timeoutSeconds: Int) throws -> [String: Any] {
        let fd = try connectSocket(timeoutSeconds: timeoutSeconds)
        defer { close(fd) }

        let payload = try JSONSerialization.data(withJSONObject: request)
        try payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            guard Darwin.write(fd, base, payload.count) >= 0 else {
                throw NSError(domain: "wiredsyncd.ipc", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to write request to wiredsyncd"])
            }
            _ = Darwin.write(fd, "\n", 1)
        }

        var responseBuffer = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &responseBuffer, responseBuffer.count)
        guard n > 0 else {
            throw NSError(
                domain: "wiredsyncd.ipc",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No response from wiredsyncd (timeout \(timeoutSeconds)s)"]
            )
        }

        let data = Data(responseBuffer.prefix(n))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "wiredsyncd.ipc", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid response from wiredsyncd"])
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw NSError(domain: "wiredsyncd.ipc", code: 6, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return json
    }

    private static func connectSocket(timeoutSeconds: Int) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "wiredsyncd.ipc", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(socketPath.utf8.prefix(maxLen - 1))
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            raw.initialize(repeating: 0, count: maxLen)
            for (index, byte) in bytes.enumerated() {
                raw[index] = CChar(bitPattern: byte)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + maxLen)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addrLen)
            }
        }
        guard result == 0 else {
            close(fd)
            throw NSError(
                domain: "wiredsyncd.ipc",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to connect to wiredsyncd socket at \(socketPath)"]
            )
        }

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        withUnsafePointer(to: &timeout) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { rawPtr in
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, rawPtr, socklen_t(MemoryLayout<timeval>.size))
                _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, rawPtr, socklen_t(MemoryLayout<timeval>.size))
            }
        }

        return fd
    }

    private static func installAndStartLaunchAgent() throws {
        let fm = FileManager.default
        let launchAgentsDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Library/LaunchAgents")
        let logDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Library/Logs/WiredSync")
        try fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: runPath, withIntermediateDirectories: true)

        let daemonPath = try installDaemonArtifacts()
        try? fm.removeItem(atPath: socketPath)
        print("[WiredSyncUI] launchd.install daemon=\(daemonPath) resource_root=\(daemonResourcesPath)")

        var environmentVariables: [String: String] = [
            "WIRED_SYNCD_RESOURCE_ROOT": daemonResourcesPath,
            "WIRED_APPLICATION_NAME": "wiredsyncd"
        ]
        if let version = wiredSyncApplicationVersion {
            environmentVariables["WIRED_APPLICATION_VERSION"] = version
        }
        if let build = wiredSyncApplicationBuild {
            environmentVariables["WIRED_APPLICATION_BUILD"] = build
        }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [daemonPath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "WorkingDirectory": daemonInstallPath,
            "EnvironmentVariables": environmentVariables,
            "StandardOutPath": (logDir as NSString).appendingPathComponent("wiredsyncd.out.log"),
            "StandardErrorPath": (logDir as NSString).appendingPathComponent("wiredsyncd.err.log"),
            "ProcessType": "Background",
            "ThrottleInterval": 1
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: launchAgentPath), options: .atomic)

        let domain = "gui/\(getuid())"
        _ = try runLaunchctl(arguments: ["bootout", "\(domain)/\(launchAgentLabel)"], allowFailure: true)
        _ = try runLaunchctl(arguments: ["bootout", domain, launchAgentPath], allowFailure: true)
        _ = try runLaunchctl(arguments: ["enable", "\(domain)/\(launchAgentLabel)"], allowFailure: true)
        _ = try runLaunchctl(arguments: ["bootstrap", domain, launchAgentPath], allowFailure: false)
        try waitForDaemonReady()
    }

    private static func installDaemonArtifacts() throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(atPath: daemonInstallPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: daemonResourcesPath, withIntermediateDirectories: true)

        let sourceBinaryPath = try resolveBundledDaemonExecutablePath()
        try installFile(from: sourceBinaryPath, to: installedDaemonPath, executable: true)

        if let resourcePath = resolveBundledDaemonResourcePath() {
            let installedResourcePath = (daemonResourcesPath as NSString).appendingPathComponent("wired.xml")
            try installFile(from: resourcePath, to: installedResourcePath, executable: false)
        }

        return installedDaemonPath
    }

    private static func installFile(from sourcePath: String, to destinationPath: String, executable: Bool) throws {
        let fm = FileManager.default
        let tempPath = destinationPath + ".tmp"
        try? fm.removeItem(atPath: tempPath)
        if fm.fileExists(atPath: destinationPath) {
            try fm.removeItem(atPath: destinationPath)
        }
        try fm.copyItem(atPath: sourcePath, toPath: tempPath)
        if executable {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempPath)
        } else {
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempPath)
        }
        try fm.moveItem(atPath: tempPath, toPath: destinationPath)
    }

    private static func resolveBundledDaemonExecutablePath() throws -> String {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        var candidates: [String] = []
        if let fromEnv = env["WIRED_SYNCD_PATH"], !fromEnv.isEmpty {
            candidates.append(fromEnv)
        }
        if let aux = Bundle.main.url(forAuxiliaryExecutable: "wiredsyncd")?.path {
            candidates.append(aux)
        }
        candidates.append((Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/MacOS/wiredsyncd"))
        candidates.append((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("wiredsyncd/.build/debug/wiredsyncd"))
        candidates.append((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("wiredsyncd/.build/release/wiredsyncd"))
        candidates.append((NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/wiredsyncd"))
        candidates.append("/opt/homebrew/bin/wiredsyncd")
        candidates.append("/usr/local/bin/wiredsyncd")

        for candidate in candidates {
            if fm.fileExists(atPath: candidate), fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw NSError(
            domain: "wiredsyncd.ipc",
            code: 8,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate wiredsyncd executable. Set WIRED_SYNCD_PATH or install wiredsyncd in PATH."]
        )
    }

    private static func resolveBundledDaemonResourcePath() -> String? {
        let fm = FileManager.default
        let candidates: [String?] = [
            WiredProtocolSpec.bundledSpecURL()?.path,
            (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/wired.xml"),
            (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("WiredSwift/Sources/WiredSwift/Resources/wired.xml")
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    @discardableResult
    private static func runLaunchctl(arguments: [String], allowFailure: Bool) throws -> String {
        try runExecutable(path: "/bin/launchctl", arguments: arguments, allowFailure: allowFailure)
    }

    @discardableResult
    private static func runExecutable(path: String, arguments: [String], allowFailure: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0, !allowFailure {
            let reason = stderr.isEmpty ? stdout : stderr
            throw NSError(
                domain: "wiredsyncd.ipc",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: path).lastPathComponent) \(arguments.joined(separator: " ")) failed: \(reason)"]
            )
        }

        return stdout + stderr
    }

    private static func waitForDaemonReady(timeout: TimeInterval = 15.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) {
                do {
                    let response = try performRequest(
                        ["jsonrpc": "2.0", "id": UUID().uuidString, "method": "status"],
                        timeoutSeconds: 1
                    )
                    if let result = response["result"] as? [String: Any],
                       let version = result["version"] as? String,
                       version == expectedDaemonVersion {
                        print("[WiredSyncUI] launchd.ready socket=\(socketPath) version=\(version)")
                        return
                    }
                } catch {
                    lastError = error
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let reason = (lastError as NSError?)?.localizedDescription ?? "socket did not become ready"
        print("[WiredSyncUI] launchd.timeout socket=\(socketPath) reason=\(reason)")
        throw NSError(
            domain: "wiredsyncd.ipc",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "wiredsyncd launchd startup timed out: \(reason)"]
        )
    }

    static func waitForPairRegistration(
        remotePath: String,
        serverURL: String,
        login: String,
        timeout: TimeInterval = 5.0
    ) throws {
        let normalizedPath = normalizeSyncRemotePath(remotePath)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if persistedPairedRemotePaths(serverURL: serverURL, login: login).contains(normalizedPath) {
                return
            }
            if let livePaths = try? listPairedRemotePaths(serverURL: serverURL, login: login),
               livePaths.contains(normalizedPath) {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw NSError(
            domain: "wiredsyncd.ipc",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "wiredsyncd did not confirm the pair for \(remotePath) on \(serverURL) as \(login)."]
        )
    }

    static func ensureDaemonIsCurrentVersion() {
        Task.detached(priority: .background) {
            do {
                let result = try performRequest(
                    ["jsonrpc": "2.0", "id": UUID().uuidString, "method": "status"],
                    timeoutSeconds: 3
                )
                let data = result["result"] as? [String: Any]
                let runningVersion = data?["version"] as? String ?? ""
                guard runningVersion != expectedDaemonVersion else { return }
                print("[WiredSyncUI] daemon.version_mismatch running=\(runningVersion) expected=\(expectedDaemonVersion) – reinstalling")
            } catch {
                let fm = FileManager.default
                guard fm.fileExists(atPath: launchAgentPath) || fm.fileExists(atPath: installedDaemonPath) else {
                    return
                }
                print("[WiredSyncUI] daemon.status_unavailable expected=\(expectedDaemonVersion) error=\(error.localizedDescription) – reinstalling")
            }

            do {
                try installAndStartLaunchAgent()
                print("[WiredSyncUI] daemon.version_update_ok version=\(expectedDaemonVersion)")
            } catch {
                print("[WiredSyncUI] daemon.version_update_failed error=\(error.localizedDescription)")
            }
        }
    }
}
