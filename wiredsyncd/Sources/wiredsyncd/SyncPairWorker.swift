import Foundation
import Darwin
import WiredSwift
final class SyncPairWorker {
    private let pair: SyncPair
    private let store: SQLiteStore
    private let secrets: SecretStore
    private let specPath: String
    private let log: (String) -> Void
    private let clientInfoDelegate = DaemonClientInfoDelegate()

    init(pair: SyncPair, store: SQLiteStore, secrets: SecretStore, specPath: String, log: @escaping (String) -> Void) {
        self.pair = pair
        self.store = store
        self.secrets = secrets
        self.specPath = specPath
        self.log = log
    }

    private func withTimeout<T>(seconds: Double, label: String, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let ns = UInt64(max(0.1, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw NSError(
                    domain: "wiredsyncd.sync",
                    code: 901,
                    userInfo: [NSLocalizedDescriptionKey: "Timeout (\(Int(seconds))s) during \(label)"]
                )
            }
            guard let first = try await group.next() else {
                throw NSError(domain: "wiredsyncd.sync", code: 902, userInfo: [NSLocalizedDescriptionKey: "Timeout group failed for \(label)"])
            }
            group.cancelAll()
            return first
        }
    }

    func runOnce() async throws {
        let spec = P7Spec(withPath: specPath)
        let control = AsyncConnection(withSpec: spec)
        control.clientInfoDelegate = clientInfoDelegate
        control.nick = DaemonIdentity.nick(forRemotePath: pair.remotePath)
        control.icon = DaemonIdentity.folderIconBase64()
        control.interactive = true
        let url = try await connectControlIfNeeded(connection: control)
        defer { disconnectControl(connection: control) }

        _ = try await runCycle(connection: control, spec: spec, url: url)
    }

    func runCycle(connection control: AsyncConnection, spec: P7Spec, url: Url) async throws -> Bool {
        try prepareLocalRoot()
        let remoteResult = try await fetchRemoteInventory(connection: control)
        let local = try await fetchLocalInventory()
        try await performReconcile(
            connection: control,
            spec: spec,
            url: url,
            remote: remoteResult.remote,
            local: local,
            allowRemotePrune: remoteResult.remoteInventoryAvailable && pair.deleteRemoteEnabled
        )
        return remoteResult.remoteInventoryAvailable
    }

    func prepareLocalRoot() throws {
        var isDirectory: ObjCBool = false
        let localExists = FileManager.default.fileExists(atPath: pair.localPath, isDirectory: &isDirectory)
        if localExists && !isDirectory.boolValue {
            throw NSError(
                domain: "wiredsyncd.sync",
                code: 951,
                userInfo: [NSLocalizedDescriptionKey: "Local sync path is not a directory: \(pair.localPath)"]
            )
        }
        if !localExists {
            if pair.mode == .clientToServer {
                throw NSError(
                    domain: "wiredsyncd.sync",
                    code: 950,
                    userInfo: [NSLocalizedDescriptionKey: "Local sync path missing for client_to_server pair: \(pair.localPath)"]
                )
            }
            try FileManager.default.createDirectory(atPath: pair.localPath, withIntermediateDirectories: true)
            log("sync.local_recreated pair=\(pair.id) path=\(pair.localPath)")
        }
    }

    func connectControlIfNeeded(connection control: AsyncConnection) async throws -> Url {
        log("sync.connect pair=\(pair.id) kind=control endpoint=\(pair.endpoint.serverURL)")

        let url = try makeURL(endpoint: resolvedEndpoint())
        try await withTimeout(seconds: 10, label: "connect") {
            try control.connect(withUrl: url)
        }
        log("sync.connected pair=\(pair.id) kind=control")
        return url
    }

    func disconnectControl(connection control: AsyncConnection) {
        log("sync.disconnect pair=\(pair.id) kind=control")
        control.disconnect()
    }

    func fetchRemoteInventory(connection control: AsyncConnection) async throws -> (remote: [String: RemoteEntry], remoteInventoryAvailable: Bool) {
        log("sync.list_remote pair=\(pair.id) path=\(pair.remotePath)")
        let remote: [String: RemoteEntry]
        var remoteInventoryAvailable = true
        do {
            remote = try await withTimeout(seconds: 20, label: "list_remote") {
                try await self.listRemoteTree(connection: control)
            }
            log("sync.list_remote_done pair=\(pair.id) items=\(remote.count)")
        } catch {
            if pair.mode == .clientToServer {
                // Write-only sync folders can legitimately deny list/read.
                // In that case we can still push local changes, but must not try remote pruning.
                remoteInventoryAvailable = false
                remote = [:]
                log("sync.list_remote_unavailable pair=\(pair.id) mode=client_to_server reason=\(error.localizedDescription)")
            } else {
                log("sync.list_remote_failed pair=\(pair.id) reason=\(error.localizedDescription)")
                throw NSError(
                    domain: "wiredsyncd.sync",
                    code: 903,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Remote listing failed; skipping sync cycle to avoid conflict amplification",
                        NSUnderlyingErrorKey: error
                    ]
                )
            }
        }
        return (remote, remoteInventoryAvailable)
    }

    func fetchLocalInventory() async throws -> [String: LocalEntry] {
        log("sync.scan_local_start pair=\(pair.id) path=\(pair.localPath)")
        let local = try await withTimeout(seconds: 20, label: "scan_local") {
            try self.scanLocalTree()
        }
        log("sync.scan_local_done pair=\(pair.id) items=\(local.count)")
        return local
    }

    func performReconcile(
        connection control: AsyncConnection,
        spec: P7Spec,
        url: Url,
        remote: [String: RemoteEntry],
        local: [String: LocalEntry],
        allowRemotePrune: Bool
    ) async throws {
        log("sync.reconcile_start pair=\(pair.id) mode=\(pair.mode.rawValue)")
        switch pair.mode {
        case .serverToClient:
            try await withTimeout(seconds: 120, label: "reconcile_server_to_client") {
                try await self.reconcileServerToClient(control: control, spec: spec, remote: remote, local: local, url: url)
            }
        case .clientToServer:
            try await withTimeout(seconds: 120, label: "reconcile_client_to_server") {
                try await self.reconcileClientToServer(
                    control: control,
                    spec: spec,
                    remote: remote,
                    local: local,
                    url: url,
                    allowRemotePrune: allowRemotePrune
                )
            }
        case .bidirectional:
            try await withTimeout(seconds: 120, label: "reconcile_bidirectional") {
                try await self.reconcileBidirectional(control: control, spec: spec, remote: remote, local: local, url: url)
            }
        }
    }

    private func makeURL(endpoint: SyncEndpoint) throws -> Url {
        let trimmed = endpoint.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "wiredsyncd.sync", code: 100, userInfo: [NSLocalizedDescriptionKey: "Missing server URL"])
        }

        let normalized = trimmed.hasPrefix("wired://") ? trimmed : "wired://\(trimmed)"
        guard var components = URLComponents(string: normalized) else {
            throw NSError(domain: "wiredsyncd.sync", code: 101, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        if !endpoint.login.isEmpty {
            components.user = endpoint.login
        }
        if !endpoint.password.isEmpty {
            components.password = endpoint.password
        }

        guard let final = components.string else {
            throw NSError(domain: "wiredsyncd.sync", code: 102, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL components"])
        }
        return Url(withString: final)
    }

    private func resolvedEndpoint() throws -> SyncEndpoint {
        var endpoint = pair.endpoint
        endpoint.password = try secrets.readPassword(pairID: pair.id) ?? ""
        return endpoint
    }

    private func listRemoteTree(connection: AsyncConnection) async throws -> [String: RemoteEntry] {
        var map: [String: RemoteEntry] = [:]
        var queue: [String] = [pair.remotePath]
        var visited: Set<String> = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if !visited.insert(current).inserted { continue }

            let message = P7Message(withName: "wired.file.list_directory", spec: connection.spec)
            message.addParameter(field: "wired.file.path", value: current)

            for try await response in try connection.sendAndWaitMany(message) {
                guard response.name == "wired.file.file_list" else { continue }

                let absolutePath = response.string(forField: "wired.file.path") ?? ""
                let relativePath = normalizedRelative(path: absolutePath, root: pair.remotePath)
                if relativePath.isEmpty { continue }
                if shouldIgnore(relativePath: relativePath) { continue }

                let type = response.uint32(forField: "wired.file.type") ?? 0
                let isDirectory = type == 1 || type == 2 || type == 3 || type == 4
                let size = response.uint64(forField: "wired.file.data_size") ?? 0
                let modificationDate = response.date(forField: "wired.file.modification_time")

                map[relativePath] = RemoteEntry(
                    relativePath: relativePath,
                    absolutePath: absolutePath,
                    isDirectory: isDirectory,
                    size: size,
                    modificationDate: modificationDate
                )

                if isDirectory {
                    queue.append(absolutePath)
                }
            }
        }

        return map
    }

    private func scanLocalTree() throws -> [String: LocalEntry] {
        var map: [String: LocalEntry] = [:]
        let root = NSString(string: pair.localPath).standardizingPath

        guard let enumerator = FileManager.default.enumerator(atPath: root) else {
            return map
        }

        while let raw = enumerator.nextObject() as? String {
            let relativePath = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relativePath.isEmpty { continue }

            if shouldIgnore(relativePath: relativePath) {
                enumerator.skipDescendants()
                continue
            }

            let absolutePath = (root as NSString).appendingPathComponent(relativePath)
            var st = stat()
            if lstat(absolutePath, &st) != 0 {
                continue
            }

            let mode = st.st_mode & S_IFMT
            let isDirectory = mode == S_IFDIR
            if !(isDirectory || mode == S_IFREG) {
                continue
            }

            let size = isDirectory ? UInt64(0) : UInt64(max(0, st.st_size))
            let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))

            map[relativePath] = LocalEntry(
                relativePath: relativePath,
                isDirectory: isDirectory,
                size: size,
                modificationDate: mtime
            )
        }

        return map
    }

    private func reconcileServerToClient(
        control: AsyncConnection,
        spec: P7Spec,
        remote: [String: RemoteEntry],
        local: [String: LocalEntry],
        url: Url
    ) async throws {
        let remoteDirs = remote.values.filter(\.isDirectory).map(\.relativePath).sorted()
        for rel in remoteDirs {
            try ensureLocalDirectory(relativePath: rel)
        }

        let remoteFiles = remote.values.filter { !$0.isDirectory }.sorted { $0.relativePath < $1.relativePath }
        for entry in remoteFiles {
            if shouldPull(remote: entry, local: local[entry.relativePath]) {
                try await downloadFile(
                    spec: spec,
                    url: url,
                    remoteAbsolutePath: entry.absolutePath,
                    localRelativePath: entry.relativePath,
                    remoteModificationDate: entry.modificationDate
                )
                try store.removeUploadedSnapshot(pairID: pair.id, relativePath: entry.relativePath)
                log("sync.pull pair=\(pair.id) path=\(entry.relativePath)")
            }
        }

        let remoteKeys = Set(remote.keys)
        let localKeys = Set(local.keys)
        let stale = localKeys.subtracting(remoteKeys).sorted { $0.count > $1.count }
        for rel in stale {
            try deleteLocal(relativePath: rel)
            try store.removeUploadedSnapshot(pairID: pair.id, relativePath: rel)
            log("sync.delete_local pair=\(pair.id) path=\(rel)")
        }
    }

    private func reconcileClientToServer(
        control: AsyncConnection,
        spec: P7Spec,
        remote: [String: RemoteEntry],
        local: [String: LocalEntry],
        url: Url,
        allowRemotePrune: Bool
    ) async throws {
        let localDirs = local.values.filter(\.isDirectory).map(\.relativePath).sorted()
        for rel in localDirs {
            try await ensureRemoteDirectory(connection: control, relativePath: rel)
        }

        let localFiles = local.values.filter { !$0.isDirectory }.sorted { $0.relativePath < $1.relativePath }
        for entry in localFiles {
            let shouldUpload: Bool
            if allowRemotePrune {
                shouldUpload = shouldPush(local: entry, remote: remote[entry.relativePath])
            } else {
                shouldUpload = shouldPushWithoutRemoteInventory(local: entry)
            }

            if shouldUpload {
                log("sync.push_try pair=\(pair.id) path=\(entry.relativePath)")
                try await uploadFile(spec: spec, url: url, localRelativePath: entry.relativePath, remoteRelativePath: entry.relativePath)
                try store.markUploaded(
                    pairID: pair.id,
                    relativePath: entry.relativePath,
                    size: entry.size,
                    modificationTime: entry.modificationDate?.timeIntervalSince1970 ?? 0
                )
                log("sync.push pair=\(pair.id) path=\(entry.relativePath)")
            }
        }

        if allowRemotePrune {
            let remoteKeys = Set(remote.keys)
            let localKeys = Set(local.keys)
            let stale = remoteKeys.subtracting(localKeys).sorted { $0.count > $1.count }
            for rel in stale {
                try await deleteRemote(connection: control, relativePath: rel)
                log("sync.delete_remote pair=\(pair.id) path=\(rel)")
            }
        } else {
            try store.pruneUploadedSnapshots(
                pairID: pair.id,
                keeping: Set(localFiles.map(\.relativePath))
            )
            log("sync.delete_remote_skipped pair=\(pair.id) reason=remote_inventory_unavailable")
        }
    }

    private func reconcileBidirectional(
        control: AsyncConnection,
        spec: P7Spec,
        remote: [String: RemoteEntry],
        local: [String: LocalEntry],
        url: Url
    ) async throws {
        let allKeys = Set(remote.keys).union(local.keys)

        for rel in allKeys.sorted() {
            let remoteEntry = remote[rel]
            let localEntry = local[rel]

            if let r = remoteEntry, r.isDirectory {
                try ensureLocalDirectory(relativePath: rel)
                continue
            }
            if let l = localEntry, l.isDirectory {
                try await ensureRemoteDirectory(connection: control, relativePath: rel)
                continue
            }

            switch (remoteEntry, localEntry) {
            case let (r?, nil):
                if !r.isDirectory {
                    if let snapshot = store.uploadedSnapshot(pairID: pair.id, relativePath: rel) {
                        // We previously synced this file. Its local absence means it was deleted locally.
                        // Exception: if remote was modified after our last upload, remote wins (re-download).
                        let remoteMtime = r.modificationDate?.timeIntervalSince1970 ?? 0
                        if remoteMtime > snapshot.modificationTime + 1.0 {
                            try await downloadFile(
                                spec: spec,
                                url: url,
                                remoteAbsolutePath: r.absolutePath,
                                localRelativePath: rel,
                                remoteModificationDate: r.modificationDate
                            )
                            log("sync.pull pair=\(pair.id) path=\(rel) reason=local_deleted_remote_modified")
                        } else {
                            try await deleteRemote(connection: control, relativePath: rel)
                            try store.removeUploadedSnapshot(pairID: pair.id, relativePath: rel)
                            log("sync.delete_remote pair=\(pair.id) path=\(rel) reason=local_deleted")
                        }
                    } else {
                        // No snapshot — new remote file, download it.
                        try await downloadFile(
                            spec: spec,
                            url: url,
                            remoteAbsolutePath: r.absolutePath,
                            localRelativePath: rel,
                            remoteModificationDate: r.modificationDate
                        )
                        log("sync.pull pair=\(pair.id) path=\(rel)")
                    }
                }

            case let (nil, l?):
                if !l.isDirectory {
                    if let snapshot = store.uploadedSnapshot(pairID: pair.id, relativePath: rel) {
                        // We previously synced this file. Its remote absence means it was deleted remotely.
                        // Exception: if local was modified since our last upload, local wins (re-upload).
                        let localMtime = l.modificationDate?.timeIntervalSince1970 ?? 0
                        if snapshot.size != l.size || abs(snapshot.modificationTime - localMtime) > 1.0 {
                            log("sync.push_try pair=\(pair.id) path=\(rel) reason=remote_deleted_local_modified")
                            try await uploadFile(spec: spec, url: url, localRelativePath: rel, remoteRelativePath: rel)
                            try store.markUploaded(
                                pairID: pair.id,
                                relativePath: rel,
                                size: l.size,
                                modificationTime: localMtime
                            )
                            log("sync.push pair=\(pair.id) path=\(rel) reason=remote_deleted_local_modified")
                        } else {
                            try deleteLocal(relativePath: rel)
                            try store.removeUploadedSnapshot(pairID: pair.id, relativePath: rel)
                            log("sync.delete_local pair=\(pair.id) path=\(rel) reason=remote_deleted")
                        }
                    } else {
                        // No snapshot — new local file, upload it.
                        log("sync.push_try pair=\(pair.id) path=\(rel)")
                        try await uploadFile(spec: spec, url: url, localRelativePath: rel, remoteRelativePath: rel)
                        try store.markUploaded(
                            pairID: pair.id,
                            relativePath: rel,
                            size: l.size,
                            modificationTime: l.modificationDate?.timeIntervalSince1970 ?? 0
                        )
                        log("sync.push pair=\(pair.id) path=\(rel)")
                    }
                }

            case let (r?, l?):
                guard !r.isDirectory && !l.isDirectory else { continue }

                // If the local file matches our last-uploaded snapshot, the remote mtime
                // difference is caused by our own previous upload (the server assigned its
                // own timestamp). Treat the file as in-sync to break the push→pull loop.
                if let snapshot = store.uploadedSnapshot(pairID: pair.id, relativePath: rel) {
                    let localMtime = l.modificationDate?.timeIntervalSince1970 ?? 0
                    if snapshot.size == l.size && abs(snapshot.modificationTime - localMtime) <= 1.0 {
                        continue
                    }
                }

                let remoteDate = r.modificationDate
                let localDate = l.modificationDate
                let sizeDiffers = r.size != l.size
                let remoteTimestamp = remoteDate?.timeIntervalSince1970 ?? 0
                let localTimestamp = localDate?.timeIntervalSince1970 ?? 0
                let mtimeDiffers = abs(remoteTimestamp - localTimestamp) > 1.0

                if !sizeDiffers && !mtimeDiffers {
                    continue
                }

                if let remoteDate, let localDate {
                    let delta = remoteDate.timeIntervalSince(localDate)
                    if delta > 1.0 {
                        try await downloadFile(
                            spec: spec,
                            url: url,
                            remoteAbsolutePath: r.absolutePath,
                            localRelativePath: rel,
                            remoteModificationDate: r.modificationDate
                        )
                        try store.removeUploadedSnapshot(pairID: pair.id, relativePath: rel)
                        log("sync.pull pair=\(pair.id) path=\(rel)")
                    } else if delta < -1.0 {
                        try await uploadFile(spec: spec, url: url, localRelativePath: rel, remoteRelativePath: rel)
                        try store.markUploaded(
                            pairID: pair.id,
                            relativePath: rel,
                            size: l.size,
                            modificationTime: l.modificationDate?.timeIntervalSince1970 ?? 0
                        )
                        log("sync.push pair=\(pair.id) path=\(rel)")
                    } else {
                        // Avoid conflict amplification when mtimes are too close to compare reliably.
                        // Deterministic tie-break: local side wins.
                        try await uploadFile(spec: spec, url: url, localRelativePath: rel, remoteRelativePath: rel)
                        try store.markUploaded(
                            pairID: pair.id,
                            relativePath: rel,
                            size: l.size,
                            modificationTime: l.modificationDate?.timeIntervalSince1970 ?? 0
                        )
                        log("sync.push pair=\(pair.id) path=\(rel) reason=mtime_tie")
                    }
                } else if remoteDate != nil {
                    try await downloadFile(
                        spec: spec,
                        url: url,
                        remoteAbsolutePath: r.absolutePath,
                        localRelativePath: rel,
                        remoteModificationDate: r.modificationDate
                    )
                    try store.removeUploadedSnapshot(pairID: pair.id, relativePath: rel)
                    log("sync.pull pair=\(pair.id) path=\(rel) reason=remote_mtime_only")
                } else if localDate != nil {
                    try await uploadFile(spec: spec, url: url, localRelativePath: rel, remoteRelativePath: rel)
                    try store.markUploaded(
                        pairID: pair.id,
                        relativePath: rel,
                        size: l.size,
                        modificationTime: l.modificationDate?.timeIntervalSince1970 ?? 0
                    )
                    log("sync.push pair=\(pair.id) path=\(rel) reason=local_mtime_only")
                } else {
                    try await uploadFile(spec: spec, url: url, localRelativePath: rel, remoteRelativePath: rel)
                    try store.markUploaded(
                        pairID: pair.id,
                        relativePath: rel,
                        size: l.size,
                        modificationTime: l.modificationDate?.timeIntervalSince1970 ?? 0
                    )
                    log("sync.push pair=\(pair.id) path=\(rel) reason=no_mtime")
                }

            case (nil, nil):
                continue
            }
        }
    }

    private func resolveConflict(spec: P7Spec, url: Url, relativePath: String, remoteAbsolutePath: String) async throws {
        let localPath = localAbsolute(relativePath: relativePath)
        let localConflict = conflictPath(for: localPath)
        let remoteConflictRelative = conflictPath(for: relativePath)

        if FileManager.default.fileExists(atPath: localPath) {
            try FileManager.default.copyItem(atPath: localPath, toPath: localConflict)
        }

        try await downloadFile(
            spec: spec,
            url: url,
            remoteAbsolutePath: remoteAbsolutePath,
            localRelativePath: relativePath,
            remoteModificationDate: nil
        )
        if FileManager.default.fileExists(atPath: localConflict) {
            try await uploadFile(spec: spec, url: url, localRelativePath: normalizedRelative(path: localConflict, root: pair.localPath), remoteRelativePath: remoteConflictRelative)
        }

        log("sync.conflict pair=\(pair.id) path=\(relativePath)")
    }

    private func shouldPull(remote: RemoteEntry, local: LocalEntry?) -> Bool {
        guard let local else { return true }
        guard !local.isDirectory else { return true }
        if remote.size != local.size {
            return true
        }
        let remoteModificationTime = remote.modificationDate?.timeIntervalSince1970 ?? 0
        let localModificationTime = local.modificationDate?.timeIntervalSince1970 ?? 0
        return abs(remoteModificationTime - localModificationTime) > 1.0
    }

    private func shouldPush(local: LocalEntry, remote: RemoteEntry?) -> Bool {
        guard let remote else { return true }
        guard !remote.isDirectory else { return true }
        if local.size != remote.size {
            return true
        }
        if let snapshot = store.uploadedSnapshot(pairID: pair.id, relativePath: local.relativePath) {
            let localModificationTime = local.modificationDate?.timeIntervalSince1970 ?? 0
            if snapshot.size == local.size,
               abs(snapshot.modificationTime - localModificationTime) <= 1.0 {
                return false
            }
        }
        let localModificationTime = local.modificationDate?.timeIntervalSince1970 ?? 0
        let remoteModificationTime = remote.modificationDate?.timeIntervalSince1970 ?? 0
        return abs(localModificationTime - remoteModificationTime) > 1.0
    }

    private func shouldPushWithoutRemoteInventory(local: LocalEntry) -> Bool {
        guard let snapshot = store.uploadedSnapshot(pairID: pair.id, relativePath: local.relativePath) else {
            return true
        }
        let localModificationTime = local.modificationDate?.timeIntervalSince1970 ?? 0
        return snapshot.size != local.size || abs(snapshot.modificationTime - localModificationTime) > 1.0
    }

    private func ensureLocalDirectory(relativePath: String) throws {
        let absolute = localAbsolute(relativePath: relativePath)
        try FileManager.default.createDirectory(atPath: absolute, withIntermediateDirectories: true)
    }

    private func ensureRemoteDirectory(connection: AsyncConnection, relativePath: String) async throws {
        let absolutePath = remoteAbsolute(relativePath: relativePath)
        let message = P7Message(withName: "wired.transfer.upload_directory", spec: connection.spec)
        message.addParameter(field: "wired.file.path", value: absolutePath)
        do {
            _ = try await connection.sendAsync(message)
        } catch let AsyncConnectionError.serverError(message) {
            let code = message.enumeration(forField: "wired.error") ?? 0
            // wired.error.file_exists = 15
            if code != 15 {
                throw AsyncConnectionError.serverError(message)
            }
        }
    }

    private func deleteRemote(connection: AsyncConnection, relativePath: String) async throws {
        let message = P7Message(withName: "wired.file.delete", spec: connection.spec)
        message.addParameter(field: "wired.file.path", value: remoteAbsolute(relativePath: relativePath))
        _ = try await connection.sendAsync(message)
    }

    private func deleteLocal(relativePath: String) throws {
        let absolute = localAbsolute(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: absolute) else { return }
        try FileManager.default.removeItem(atPath: absolute)
    }

    private func downloadFile(
        spec: P7Spec,
        url: Url,
        remoteAbsolutePath: String,
        localRelativePath: String,
        remoteModificationDate: Date?
    ) async throws {
        log("sync.transfer_connect pair=\(pair.id) kind=download path=\(localRelativePath)")
        let tconn = AsyncConnection(withSpec: spec)
        tconn.clientInfoDelegate = clientInfoDelegate
        tconn.nick = DaemonIdentity.nick(forRemotePath: pair.remotePath)
        tconn.icon = DaemonIdentity.folderIconBase64()
        tconn.interactive = false
        try tconn.connect(withUrl: url)
        defer {
            log("sync.transfer_disconnect pair=\(pair.id) kind=download path=\(localRelativePath)")
            tconn.disconnect()
        }

        let localPath = localAbsolute(relativePath: localRelativePath)
        let parent = (localPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

        let request = P7Message(withName: "wired.transfer.download_file", spec: spec)
        request.addParameter(field: "wired.file.path", value: remoteAbsolutePath)
        request.addParameter(field: "wired.transfer.data_offset", value: UInt64(0))
        request.addParameter(field: "wired.transfer.rsrc_offset", value: UInt64(0))

        guard tconn.send(message: request) else {
            throw NSError(domain: "wiredsyncd.sync", code: 200, userInfo: [NSLocalizedDescriptionKey: "Unable to request remote download"])
        }

        let runMessage = try waitForTransferMessage(connection: tconn, expected: "wired.transfer.download")
        let dataLength = runMessage.uint64(forField: "wired.transfer.data") ?? 0
        let rsrcLength = runMessage.uint64(forField: "wired.transfer.rsrc") ?? 0

        let tmpPath = "\(localPath).wiredsync.part"
        _ = FileManager.default.createFile(atPath: tmpPath, contents: Data())
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tmpPath))
        defer { try? handle.close() }

        var remainingData = dataLength
        while remainingData > 0 {
            let chunk = try tconn.socket.readOOB(timeout: 120)
            handle.write(chunk)
            remainingData = (remainingData > UInt64(chunk.count)) ? (remainingData - UInt64(chunk.count)) : 0
        }

        var remainingRsrc = rsrcLength
        while remainingRsrc > 0 {
            let chunk = try tconn.socket.readOOB(timeout: 120)
            remainingRsrc = (remainingRsrc > UInt64(chunk.count)) ? (remainingRsrc - UInt64(chunk.count)) : 0
        }

        if FileManager.default.fileExists(atPath: localPath) {
            try FileManager.default.removeItem(atPath: localPath)
        }
        try FileManager.default.moveItem(atPath: tmpPath, toPath: localPath)
        if let remoteModificationDate {
            try? FileManager.default.setAttributes([.modificationDate: remoteModificationDate], ofItemAtPath: localPath)
        }
    }

    private func uploadFile(spec: P7Spec, url: Url, localRelativePath: String, remoteRelativePath: String) async throws {
        let localPath = localAbsolute(relativePath: localRelativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: localPath)
        let expectedSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

        log("sync.transfer_connect pair=\(pair.id) kind=upload path=\(localRelativePath)")
        let tconn = AsyncConnection(withSpec: spec)
        tconn.clientInfoDelegate = clientInfoDelegate
        tconn.nick = DaemonIdentity.nick(forRemotePath: pair.remotePath)
        tconn.icon = DaemonIdentity.folderIconBase64()
        tconn.interactive = false
        try tconn.connect(withUrl: url)
        defer {
            log("sync.transfer_disconnect pair=\(pair.id) kind=upload path=\(localRelativePath)")
            tconn.disconnect()
        }

        let remoteAbsolutePath = remoteAbsolute(relativePath: remoteRelativePath)

        let uploadFile = P7Message(withName: "wired.transfer.upload_file", spec: spec)
        uploadFile.addParameter(field: "wired.file.path", value: remoteAbsolutePath)
        uploadFile.addParameter(field: "wired.transfer.data_size", value: expectedSize)
        uploadFile.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))

        guard tconn.send(message: uploadFile) else {
            throw NSError(domain: "wiredsyncd.sync", code: 201, userInfo: [NSLocalizedDescriptionKey: "Unable to request remote upload"])
        }

        let ready = try waitForTransferMessage(connection: tconn, expected: "wired.transfer.upload_ready")
        let offset = ready.uint64(forField: "wired.transfer.data_offset") ?? 0

        let upload = P7Message(withName: "wired.transfer.upload", spec: spec)
        upload.addParameter(field: "wired.file.path", value: remoteAbsolutePath)
        upload.addParameter(field: "wired.transfer.data", value: expectedSize > offset ? expectedSize - offset : UInt64(0))
        upload.addParameter(field: "wired.transfer.rsrc", value: UInt64(0))
        upload.addParameter(field: "wired.transfer.finderinfo", value: Data(count: 32).base64EncodedData())

        guard tconn.send(message: upload) else {
            throw NSError(domain: "wiredsyncd.sync", code: 202, userInfo: [NSLocalizedDescriptionKey: "Unable to start remote upload"])
        }

        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: localPath))
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: offset)

        var remaining = expectedSize > offset ? expectedSize - offset : UInt64(0)
        while remaining > 0 {
            let chunk = try fileHandle.read(upToCount: min(65_536, Int(remaining))) ?? Data()
            if chunk.isEmpty {
                throw NSError(domain: "wiredsyncd.sync", code: 203, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF while uploading \(localPath)"])
            }
            try tconn.socket.writeOOB(data: chunk, timeout: 120)
            remaining -= UInt64(chunk.count)
        }
    }

    private func waitForTransferMessage(connection: AsyncConnection, expected: String) throws -> P7Message {
        while true {
            let message = try connection.readMessage()

            if message.name == expected {
                return message
            }

            if message.name == "wired.send_ping" || message.name == "wired.transfer.send_ping" {
                let reply = P7Message(withName: "wired.ping", spec: connection.spec)
                if let transaction = message.uint32(forField: "wired.transaction") {
                    reply.addParameter(field: "wired.transaction", value: transaction)
                }
                _ = connection.send(message: reply)
                continue
            }

            if message.name == "wired.transfer.queue" {
                continue
            }

            if message.name == "wired.error" {
                let code = message.enumeration(forField: "wired.error") ?? 0
                let text = message.string(forField: "wired.error.string") ?? "No error message"
                let detail = "wired.error(code=\(code), message=\(text), expected=\(expected))"
                throw NSError(domain: "wiredsyncd.sync", code: 204, userInfo: [NSLocalizedDescriptionKey: detail])
            }
        }
    }

    private func localAbsolute(relativePath: String) -> String {
        (pair.localPath as NSString).appendingPathComponent(relativePath)
    }

    private func remoteAbsolute(relativePath: String) -> String {
        normalizedJoin(base: pair.remotePath, relative: relativePath)
    }

    private func normalizedRelative(path: String, root: String) -> String {
        let p = NSString(string: path).standardizingPath
        let r = NSString(string: root).standardizingPath
        if p == r { return "" }
        guard p.hasPrefix(r) else { return p.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        var rel = String(p.dropFirst(r.count))
        while rel.hasPrefix("/") {
            rel.removeFirst()
        }
        return rel
    }

    private func normalizedJoin(base: String, relative: String) -> String {
        if relative.isEmpty { return base }
        if base == "/" {
            return "/\(relative)"
        }
        return (base as NSString).appendingPathComponent(relative)
    }

    private func containsHiddenPathComponent(_ relativePath: String) -> Bool {
        syncPathContainsHiddenPathComponent(relativePath)
    }

    private func isConflictArtifact(relativePath: String) -> Bool {
        syncPathIsConflictArtifact(relativePath)
    }

    private func isTransientTransferArtifact(relativePath: String) -> Bool {
        syncPathIsTransientTransferArtifact(relativePath)
    }

    /// Returns true if `relativePath` matches any of the pair's exclude patterns.
    /// Patterns without a "/" are matched against the last path component only (like .gitignore).
    /// Patterns containing "/" are matched against the full relative path.
    private func isExcluded(relativePath: String) -> Bool {
        syncPathIsExcluded(relativePath, excludePatterns: pair.excludePatterns)
    }

    private func shouldIgnore(relativePath: String) -> Bool {
        containsHiddenPathComponent(relativePath)
            || isConflictArtifact(relativePath: relativePath)
            || isTransientTransferArtifact(relativePath: relativePath)
            || isExcluded(relativePath: relativePath)
    }

    private func conflictPath(for path: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let username = pair.endpoint.login.isEmpty ? "user" : pair.endpoint.login
        let base = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        if ext.isEmpty {
            return "\(base).conflict.\(username).\(timestamp)"
        }
        return "\(base).conflict.\(username).\(timestamp).\(ext)"
    }
}
