import Foundation
import Darwin
import AppKit
import WiredSwift
func describeSyncError(_ error: Error) -> String {
    let nsError = error as NSError
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
        return describeSyncError(underlying)
    }
    if let wired = error as? WiredError {
        return wired.description
    }
    if let asyncError = error as? AsyncConnectionError {
        switch asyncError {
        case .notConnected:
            return "AsyncConnectionError.notConnected"
        case .writeFailed:
            return "AsyncConnectionError.writeFailed"
        case .serverError(let message):
            let code = message.enumeration(forField: "wired.error") ?? 0
            let text = message.string(forField: "wired.error.string") ?? "No server message"
            return "AsyncConnectionError.serverError(code=\(code), message=\(text))"
        }
    }
    if !nsError.localizedDescription.isEmpty {
        return nsError.localizedDescription
    }
    return String(describing: error)
}

func setSocketPermissions(path: String) {
    chmod(path, mode_t(S_IRUSR | S_IWUSR))
}

func setClientReadTimeout(fd: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    withUnsafePointer(to: &timeout) { ptr in
        ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { raw in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, raw, socklen_t(MemoryLayout<timeval>.size))
        }
    }
}

func verifyPeerUID(_ clientFD: Int32) -> Bool {
    var uid = uid_t()
    var gid = gid_t()
    if getpeereid(clientFD, &uid, &gid) != 0 {
        return false
    }
    return uid == geteuid()
}

func socketAddr(path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    let bytes = Array(path.utf8.prefix(maxLen - 1))
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
        raw.initialize(repeating: 0, count: maxLen)
        for (i, b) in bytes.enumerated() {
            raw[i] = CChar(bitPattern: b)
        }
    }
    return addr
}

func sendJSON(_ object: Any, to fd: Int32) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
        return
    }
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        _ = Darwin.write(fd, base, data.count)
        _ = Darwin.write(fd, "\n", 1)
    }
}

func readLine(from fd: Int32) -> String? {
    var buffer = [UInt8](repeating: 0, count: 16384)
    let n = Darwin.read(fd, &buffer, buffer.count)
    guard n > 0 else { return nil }
    return String(decoding: buffer[0..<n], as: UTF8.self)
}

func decodeRequest(_ text: String) -> RPCRequest? {
    guard let data = text.data(using: .utf8) else { return nil }
    if let request = try? JSONDecoder().decode(RPCRequest.self, from: data) {
        return request
    }
    if let first = text.split(separator: "\n").first,
       let data = first.data(using: .utf8),
       let request = try? JSONDecoder().decode(RPCRequest.self, from: data) {
        return request
    }
    return nil
}

func respondError(id: String?, code: Int, message: String, fd: Int32) {
    let payload: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id as Any,
        "error": ["code": code, "message": message]
    ]
    sendJSON(payload, to: fd)
}

func respondResult(id: String?, result: [String: Any], fd: Int32) {
    let payload: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id as Any,
        "result": result
    ]
    sendJSON(payload, to: fd)
}

func handleRequest(_ req: RPCRequest, state: DaemonState, engine: SyncEngine, fd: Int32) {
    let params = req.params ?? [:]
    switch req.method {
    case "status":
        respondResult(id: req.id, result: state.status(), fd: fd)

    case "list_pairs":
        let rows = state.snapshotPairs().map { pair in
            let runtime = state.runtimeStatus(pairID: pair.id)
            return [
                "id": pair.id,
                "remote_path": pair.remotePath,
                "local_path": pair.localPath,
                "mode": pair.mode.rawValue,
                "delete_remote_enabled": pair.deleteRemoteEnabled ? "true" : "false",
                "server_url": pair.endpoint.serverURL,
                "login": pair.endpoint.login,
                "paused": pair.paused ? "true" : "false",
                "runtime_state": runtime?.state.rawValue ?? (pair.paused ? PairConnectionState.paused.rawValue : PairConnectionState.disconnected.rawValue),
                "runtime_last_error": runtime?.lastError as Any,
                "runtime_retry_count": runtime?.retryCount ?? 0,
                "runtime_next_retry_at": runtime?.nextRetryAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
                "runtime_last_connected_at": runtime?.lastConnectedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
                "runtime_last_sync_started_at": runtime?.lastSyncStartedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
                "runtime_last_sync_completed_at": runtime?.lastSyncCompletedAt.map { ISO8601DateFormatter().string(from: $0) } as Any
            ]
        }
        respondResult(id: req.id, result: ["ok": true, "pairs": rows], fd: fd)

    case "add_pair":
        guard let remotePath = params["remote_path"],
              let localPath = params["local_path"] else {
            respondError(id: req.id, code: -32602, message: "remote_path/local_path required", fd: fd)
            return
        }
        let mode = SyncMode(rawValue: params["mode"] ?? "bidirectional") ?? .bidirectional
        let deleteRemoteEnabledRaw = (params["delete_remote_enabled"] ?? "false").lowercased()
        let deleteRemoteEnabled = deleteRemoteEnabledRaw == "true" || deleteRemoteEnabledRaw == "1"
        let excludePatterns = (params["exclude_patterns"] ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let endpoint = SyncEndpoint(
            serverURL: params["server_url"] ?? "",
            login: params["login"] ?? "",
            password: params["password"] ?? ""
        )
        guard !endpoint.serverURL.isEmpty else {
            respondError(id: req.id, code: -32602, message: "server_url required for standalone daemon", fd: fd)
            return
        }

        do {
            let pair = try state.addPair(
                remotePath: remotePath,
                localPath: localPath,
                mode: mode,
                deleteRemoteEnabled: deleteRemoteEnabled,
                excludePatterns: excludePatterns,
                endpoint: endpoint
            )
            engine.handlePairAdded(pair.id)
            respondResult(id: req.id, result: ["ok": true, "pair_id": pair.id], fd: fd)
        } catch {
            respondError(id: req.id, code: -32000, message: "add_pair failed: \(error.localizedDescription)", fd: fd)
        }

    case "remove_pair":
        guard let pairID = params["pair_id"] else {
            respondError(id: req.id, code: -32602, message: "pair_id required", fd: fd)
            return
        }
        do {
            let ok = try state.removePair(id: pairID)
            if ok {
                engine.handlePairRemoved(pairID)
            }
            respondResult(id: req.id, result: ["ok": ok], fd: fd)
        } catch {
            respondError(id: req.id, code: -32000, message: "remove_pair failed: \(error.localizedDescription)", fd: fd)
        }

    case "remove_pair_for_remote":
        guard let remotePath = params["remote_path"] else {
            respondError(id: req.id, code: -32602, message: "remote_path required", fd: fd)
            return
        }
        do {
            let removed = try state.removePairs(remotePath: remotePath, serverURL: params["server_url"], login: params["login"])
            engine.handlePairsRemoved(removed)
            respondResult(
                id: req.id,
                result: [
                    "ok": true,
                    "removed_count": removed.count,
                    "removed_ids": removed
                ],
                fd: fd
            )
        } catch {
            respondError(id: req.id, code: -32000, message: "remove_pair_for_remote failed: \(error.localizedDescription)", fd: fd)
        }

    case "rename_pair_remote":
        guard let oldPath = params["old_remote_path"],
              let newPath = params["new_remote_path"] else {
            respondError(id: req.id, code: -32602, message: "old_remote_path/new_remote_path required", fd: fd)
            return
        }
        do {
            let updated = try state.renamePairRemotePath(
                oldPath: oldPath,
                newPath: newPath,
                serverURL: params["server_url"],
                login: params["login"]
            )
            for pairID in updated {
                engine.handlePairUpdated(pairID)
            }
            respondResult(
                id: req.id,
                result: [
                    "ok": true,
                    "updated_count": updated.count,
                    "updated_ids": updated
                ],
                fd: fd
            )
        } catch {
            respondError(id: req.id, code: -32000, message: "rename_pair_remote failed: \(error.localizedDescription)", fd: fd)
        }

    case "update_pair_policy", "update_pair_mode":
        guard let remotePath = params["remote_path"] else {
            respondError(id: req.id, code: -32602, message: "remote_path required", fd: fd)
            return
        }
        guard let modeRaw = params["mode"],
              let mode = SyncMode(rawValue: modeRaw) else {
            respondError(id: req.id, code: -32602, message: "valid mode required", fd: fd)
            return
        }
        let deleteRemoteEnabledRaw = (params["delete_remote_enabled"] ?? "false").lowercased()
        let deleteRemoteEnabled = deleteRemoteEnabledRaw == "true" || deleteRemoteEnabledRaw == "1"
        let updateExcludePatterns = (params["exclude_patterns"] ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            let updated = try state.updatePairPolicy(
                remotePath: remotePath,
                serverURL: params["server_url"],
                login: params["login"],
                mode: mode,
                deleteRemoteEnabled: deleteRemoteEnabled,
                excludePatterns: updateExcludePatterns
            )
            for pairID in updated {
                engine.handlePairUpdated(pairID)
            }
            respondResult(
                id: req.id,
                result: [
                    "ok": true,
                    "updated_count": updated.count,
                    "updated_ids": updated
                ],
                fd: fd
            )
        } catch {
            respondError(id: req.id, code: -32000, message: "\(req.method) failed: \(error.localizedDescription)", fd: fd)
        }

    case "pause_pair":
        guard let pairID = params["pair_id"] else {
            respondError(id: req.id, code: -32602, message: "pair_id required", fd: fd)
            return
        }
        do {
            let ok = try state.setPaused(id: pairID, paused: true)
            if ok {
                engine.handlePairPaused(pairID)
            }
            respondResult(id: req.id, result: ["ok": ok], fd: fd)
        } catch {
            respondError(id: req.id, code: -32000, message: "pause_pair failed: \(error.localizedDescription)", fd: fd)
        }

    case "resume_pair":
        guard let pairID = params["pair_id"] else {
            respondError(id: req.id, code: -32602, message: "pair_id required", fd: fd)
            return
        }
        do {
            let ok = try state.setPaused(id: pairID, paused: false)
            if ok {
                engine.handlePairResumed(pairID)
            }
            respondResult(id: req.id, result: ["ok": ok], fd: fd)
        } catch {
            respondError(id: req.id, code: -32000, message: "resume_pair failed: \(error.localizedDescription)", fd: fd)
        }

    case "reload":
        do {
            try state.reload()
            engine.handleReload()
            respondResult(id: req.id, result: ["ok": true], fd: fd)
        } catch {
            respondError(id: req.id, code: -32000, message: "reload failed: \(error.localizedDescription)", fd: fd)
        }

    case "sync_now":
        let remotePath = params["remote_path"]
        let result = engine.triggerNow(remotePath: remotePath, serverURL: params["server_url"], login: params["login"])
        if result.matched == 0 {
            respondError(
                id: req.id,
                code: -32004,
                message: "sync_now failed: no active pair found for remote_path \(remotePath ?? "*") server_url \(params["server_url"] ?? "*") login \(params["login"] ?? "*")",
                fd: fd
            )
            return
        }
        state.appendLog("sync.now remote=\(remotePath ?? "*") matched=\(result.matched) launched=\(result.launched)")
        respondResult(
            id: req.id,
            result: [
                "ok": true,
                "matched": result.matched,
                "launched": result.launched
            ],
            fd: fd
        )

    case "logs_tail":
        let count = Int(params["count"] ?? "50") ?? 50
        let tail = state.tail(count: count)
        respondResult(id: req.id, result: ["ok": true, "lines": tail], fd: fd)

    case "shutdown":
        state.shutdown()
        engine.stop()
        respondResult(id: req.id, result: ["ok": true], fd: fd)

    default:
        respondError(id: req.id, code: -32601, message: "method not found", fd: fd)
    }
}

func resolveEmbeddedSpecURL(paths: PathLayout) throws -> URL {
    let fm = FileManager.default
    let env = ProcessInfo.processInfo.environment
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let executableDir = executableURL.deletingLastPathComponent()

    let candidates: [URL?] = [
        WiredProtocolSpec.bundledSpecURL(),
        env["WIRED_SYNCD_RESOURCE_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("wired.xml", isDirectory: false) },
        Bundle.main.resourceURL?.appendingPathComponent("wired.xml", isDirectory: false),
        executableDir.appendingPathComponent("Resources/wired.xml", isDirectory: false),
        executableDir.appendingPathComponent("wired.xml", isDirectory: false),
        paths.baseDir.appendingPathComponent("daemon/Resources/wired.xml", isDirectory: false)
    ]

    for candidate in candidates.compactMap({ $0 }) {
        if fm.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    throw NSError(domain: "wiredsyncd", code: 21, userInfo: [NSLocalizedDescriptionKey: "Missing embedded wired.xml resource"])
}

func runServer() throws {
    let paths = PathLayout()
    try paths.ensureDirectories()
    unlink(paths.socketPath.path)

    let store = try SQLiteStore(path: paths.statePath.path)
    let state = try DaemonState(paths: paths, store: store)

    let specURL = try resolveEmbeddedSpecURL(paths: paths)

    let engine = SyncEngine(state: state, specPath: specURL.path)
    engine.start()

    let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
        throw NSError(domain: "wiredsyncd", code: 10, userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
    }
    defer { close(serverFD) }

    var addr = socketAddr(path: paths.socketPath.path)
    let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout.size(ofValue: addr.sun_path))
    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(serverFD, $0, addrLen)
        }
    }
    guard bindResult == 0 else {
        throw NSError(domain: "wiredsyncd", code: 11, userInfo: [NSLocalizedDescriptionKey: "bind() failed"])
    }

    setSocketPermissions(path: paths.socketPath.path)

    guard listen(serverFD, 16) == 0 else {
        throw NSError(domain: "wiredsyncd", code: 12, userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
    }

    state.appendLog("daemon.start socket=\(paths.socketPath.path)")

    while state.isRunning() {
        var clientAddr = sockaddr()
        var clientLen: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        let clientFD = accept(serverFD, &clientAddr, &clientLen)
        if clientFD < 0 {
            usleep(20_000)
            continue
        }

        if !verifyPeerUID(clientFD) {
            respondError(id: nil, code: -32001, message: "permission denied (uid mismatch)", fd: clientFD)
            close(clientFD)
            continue
        }

        setClientReadTimeout(fd: clientFD, seconds: 5)

        guard let line = readLine(from: clientFD), let req = decodeRequest(line) else {
            respondError(id: nil, code: -32700, message: "invalid json", fd: clientFD)
            close(clientFD)
            continue
        }

        handleRequest(req, state: state, engine: engine, fd: clientFD)
        close(clientFD)
    }

    engine.stop()
    unlink(paths.socketPath.path)
}
