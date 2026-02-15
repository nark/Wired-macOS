//
//  TransferWorker.swift
//  Wired-macOS
//
//  Transfer execution (data path) and server-queue handling.
//  Inspired by WCTransfers.m behavior.
//

import SwiftUI
import WiredSwift

actor TransferWorker {

    private let transfer: Transfer
    private let spec: P7Spec
    private let downloadRoot: String

    private let cipher: P7Socket.CipherType = .ECDH_CHACHA20_POLY1305
    private let compression: P7Socket.Compression = .LZFSE
    private let checksum: P7Socket.Checksum = .HMAC_256

    init(transfer: Transfer, spec: P7Spec, downloadRoot: String) {
        self.transfer = transfer
        self.spec = spec
        self.downloadRoot = downloadRoot
    }

    private func mutate(_ body: @MainActor (Transfer) -> Void) async {
        await MainActor.run { body(self.transfer) }
    }

    private func readState() async -> TransferState {
        await MainActor.run { self.transfer.state }
    }

    private enum Termination: Error {
        case paused
        case stopped
        case removing
    }

    private func terminationReason() async -> Termination? {
        await MainActor.run {
            switch self.transfer.state {
            case .pausing, .paused:
                return .paused
            case .stopping, .stopped, .disconnecting, .disconnected:
                return .stopped
            case .removing:
                return .removing
            default:
                return nil
            }
        }
    }

    private func isTerminating() async -> Bool {
        await terminationReason() != nil
    }

    private func finalState(for term: Termination) -> TransferState {
        switch term {
        case .paused:   return .paused
        case .stopped:  return .stopped
        case .removing: return .removing
        }
    }

    // MARK: - Entry

    func run() async {
        do {
            // A persisted transfer may have lost its live connection; without it we cannot resume.
            // Do not treat this as "finished".
            guard transfer.connection != nil else {
                await mutate {
                    $0.error = "No active connection for transfer (please reconnect to the server)"
                    $0.state = .disconnected
                }
                return
            }

            if transfer.isFolder {
                switch transfer.type {
                case .download:
                    try await runDownloadFolder()
                case .upload:
                    try await runUploadFolder()
                }
            } else {
                switch transfer.type {
                case .download:
                    try await runDownloadSingle(remotePath: transfer.remotePath!, localPath: transfer.localPath!, expectedSize: transfer.size)
                    await mutate { $0.transferredFiles = 1 }
                case .upload:
                    try await runUploadSingle(localPath: transfer.localPath!, remotePath: transfer.remotePath!, expectedSize: transfer.size)
                    await mutate { $0.transferredFiles = 1 }
                }
            }

            if let term = await terminationReason() {
                await finish(finalState(for: term))
                return
            }

            await finish(.finished)

        } catch let term as Termination {
            // User-driven termination (pause/stop/remove) should not be treated as an error.
            await finish(finalState(for: term))

        } catch {
            await mutate { $0.error = "\(error)" }

            // If we got an error while user asked to pause/stop, keep that intent.
            if await isTerminating() {
                await finish(nil)
            } else {
                await finish(.stopped)
            }
        }
    }

    // MARK: - Folder download

    private struct ListedEntry {
        let path: String
        let type: FileType
        let dataSize: UInt64
        let rsrcSize: UInt64
    }

    private func runDownloadFolder() async throws {
        guard let control = transfer.connection else {
            throw WiredError(withTitle: "Download Error", message: "Missing control connection")
        }
        guard let remoteRoot = transfer.remotePath else {
            throw WiredError(withTitle: "Download Error", message: "Missing remote path")
        }
        guard let localRoot = transfer.localPath else {
            throw WiredError(withTitle: "Download Error", message: "Missing local path")
        }

        await mutate { $0.state = .listing }
        await mutate { $0.totalFiles = 0 }
        await mutate { $0.transferredFiles = 0 }
        await mutate { $0.createdDirectories = 0 }
        await mutate { $0.size = 0 }
        await mutate { $0.actualTransferred = 0 }
        await mutate { $0.dataTransferred = 0 }
        await mutate { $0.rsrcTransferred = 0 }

        // Ensure local root exists
        try FileManager.default.createDirectory(atPath: localRoot, withIntermediateDirectories: true, attributes: nil)

        let entries = try await listRemoteDirectoryRecursive(path: remoteRoot, connection: control)

        // Build local dirs and file list
        var directories: Set<String> = []
        var files: [(remote: String, local: String, size: Int64)] = []

        for e in entries {
            let rel = relativePath(full: e.path, root: remoteRoot)
            if rel.isEmpty { continue }
            let localPath = (localRoot as NSString).appendingPathComponent(rel)

            switch e.type {
            case .directory, .uploads, .dropbox:
                directories.insert(localPath)
            case .file:
                let s = Int64(e.dataSize + e.rsrcSize)
                files.append((remote: e.path, local: localPath, size: s))
            }
        }

        await mutate { $0.totalFiles = files.count }
        await mutate { $0.size = files.reduce(0) { $0 + $1.size } }

        // Create directories
        await mutate { $0.state = .creatingDirectories }
        for dir in directories.sorted() {
            if let term = await terminationReason() { throw term }
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            await mutate { $0.createdDirectories += 1 }
        }

        // Download files sequentially
        for f in files {
            if let term = await terminationReason() { throw term }

            // Update current file
            transfer.file = FileItem((f.remote as NSString).lastPathComponent, path: f.remote)
            await mutate { $0.currentLocalFilePath = f.local }

            try await runDownloadSingle(remotePath: f.remote, localPath: f.local, expectedSize: f.size)

            await mutate { $0.transferredFiles += 1 }
        }
    }

    // MARK: - Folder upload

    private func runUploadFolder() async throws {
        guard let control = transfer.connection else {
            throw WiredError(withTitle: "Upload Error", message: "Missing control connection")
        }
        guard let localRoot = transfer.localPath else {
            throw WiredError(withTitle: "Upload Error", message: "Missing local path")
        }
        guard let remoteRoot = transfer.remotePath else {
            throw WiredError(withTitle: "Upload Error", message: "Missing remote path")
        }

        await mutate { $0.state = .listing }
        await mutate { $0.totalFiles = 0 }
        await mutate { $0.transferredFiles = 0 }
        await mutate { $0.createdDirectories = 0 }
        await mutate { $0.size = 0 }
        await mutate { $0.actualTransferred = 0 }
        await mutate { $0.dataTransferred = 0 }
        await mutate { $0.rsrcTransferred = 0 }

        // Enumerate local folder
        let enumeration = try enumerateLocalFolder(atPath: localRoot)
        await mutate { $0.totalFiles = enumeration.files.count }
        await mutate { $0.size = enumeration.files.reduce(0) { $0 + $1.size } }

        // Create remote directories (including the folder itself)
        await mutate { $0.state = .creatingDirectories }
        for dirRemotePath in enumeration.directories {
            if let term = await terminationReason() { throw term }
            try await uploadDirectory(remotePath: dirRemotePath, connection: control)
            await mutate { $0.createdDirectories += 1 }
        }

        // Upload files sequentially
        for file in enumeration.files {
            if let term = await terminationReason() { throw term }

            transfer.file = FileItem((file.remote as NSString).lastPathComponent, path: file.remote)
            await mutate { $0.currentLocalFilePath = file.local }

            try await runUploadSingle(localPath: file.local, remotePath: file.remote, expectedSize: file.size)

            await mutate { $0.transferredFiles += 1 }
        }

        // Clear current local file
        await mutate { $0.currentLocalFilePath = nil }
    }

    private struct LocalEnumeration {
        var directories: [String] = [] // remote paths
        var files: [(local: String, remote: String, size: Int64)] = []
    }

    private func enumerateLocalFolder(atPath localRoot: String) throws -> LocalEnumeration {
        guard let remoteRoot = transfer.remotePath else { return LocalEnumeration() }

        // remoteRoot already includes the folder name (destination/<name>)
        var result = LocalEnumeration()
        // Ensure remote root dir is created first
        result.directories.append(remoteRoot)

        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: localRoot)

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return result
        }

        for case let url as URL in enumerator {
            let relPath = url.path.replacingOccurrences(of: rootURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relPath.isEmpty { continue }

            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                let remoteDir = (remoteRoot as NSString).appendingPathComponent(relPath)
                result.directories.append(remoteDir)
            } else {
                let remoteFile = (remoteRoot as NSString).appendingPathComponent(relPath)
                var size: Int64 = 0
                if let fs = values.fileSize {
                    size = Int64(fs)
                } else {
                    let attrsSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                    size = attrsSize ?? 0
                }
                result.files.append((local: url.path, remote: remoteFile, size: size))
            }
        }

        // Sort for deterministic behavior (WCTransfers has consistent ordering)
        result.directories = Array(Set(result.directories)).sorted()
        result.files = result.files.sorted { $0.remote < $1.remote }

        return result
    }

    // MARK: - Single file download

    private func runDownloadSingle(remotePath: String, localPath: String, expectedSize: Int64) async throws {
        // Prepare a dedicated transfer connection
        let tconn = await ensureTransferConnection()
        tconn.interactive = false

        guard let url = transfer.connection?.url else {
            throw WiredError(withTitle: "Download Error", message: "Missing connection URL")
        }

        // Connect
        try tconn.connect(withUrl: url, cipher: cipher, compression: compression, checksum: checksum)

        transfer.speedCalculator.add(bytes: 0, time: 0)
        await mutate { $0.speed = 0 }

        // Resume support (.WiredTransfer): compute offsets from the temp file(s)
        let tmpPath = temporaryDownloadDestination(forDestination: localPath)
        let rsrcPath = FileManager.resourceForkPath(forPath: tmpPath)

        let dataOffset: Int64 = fileSize(atPath: tmpPath)
        let rsrcOffset: Int64 = fileSize(atPath: rsrcPath)
        var fileTransferred: Int64 = dataOffset + rsrcOffset

        // Ensure global counters are at least the current file offsets for single-file transfers
        // (for folder transfers, global counters already include previously completed files).
        if !transfer.isFolder {
            await mutate {
                if $0.dataTransferred < dataOffset { $0.dataTransferred = dataOffset }
                if $0.rsrcTransferred < rsrcOffset { $0.rsrcTransferred = rsrcOffset }
                let total = dataOffset + rsrcOffset
                if $0.actualTransferred < total { $0.actualTransferred = total }
            }
        }

        // Send download request
        await mutate { $0.state = .waiting }
        if !tconn.send(message: downloadFileMessage(remotePath: remotePath, dataOffset: UInt64(clamping: dataOffset), rsrcOffset: UInt64(clamping: rsrcOffset))) {
            throw WiredError(withTitle: "Download Error", message: "Cannot send download request")
        }

        guard let runMessage = await waitForMessage(on: tconn, untilReceivingMessageName: "wired.transfer.download") else {
            if let term = await terminationReason() { throw term }
            throw WiredError(withTitle: "Download Error", message: "Transfer did not start (connection closed)")
        }

        // Now we're effectively running.
        await mutate { $0.state = .running }

        var data = true
        var dataLength: UInt64 = runMessage.uint64(forField: "wired.transfer.data") ?? 0
        var rsrcLength: UInt64 = runMessage.uint64(forField: "wired.transfer.rsrc") ?? 0

        // Make sure parent dir exists
        try FileManager.default.createDirectory(atPath: (localPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)

        var time = TransfersTimeInterval()
        var speedTime = TransfersTimeInterval()
        var speedBytes = 0
        var lastUIUpdate = TransfersTimeInterval()
        let uiUpdateInterval = 0.15

        var pendingDataDelta: Int64 = 0
        var pendingRsrcDelta: Int64 = 0
        var pendingActualDelta: Int64 = 0
        var pendingSpeed: Double?

        func flushProgress(force: Bool = false) async {
            let now = TransfersTimeInterval()
            let hasPending = pendingDataDelta != 0 || pendingRsrcDelta != 0 || pendingActualDelta != 0 || pendingSpeed != nil
            guard hasPending else { return }
            if !force && now - lastUIUpdate < uiUpdateInterval && pendingSpeed == nil {
                return
            }

            let dataDelta = pendingDataDelta
            let rsrcDelta = pendingRsrcDelta
            let actualDelta = pendingActualDelta
            let speed = pendingSpeed

            pendingDataDelta = 0
            pendingRsrcDelta = 0
            pendingActualDelta = 0
            pendingSpeed = nil
            lastUIUpdate = now

            await mutate { t in
                t.dataTransferred += dataDelta
                t.rsrcTransferred += rsrcDelta
                t.actualTransferred += actualDelta
                if let speed {
                    t.speed = speed
                }
                let total = max(t.size, 1)
                t.percent = min(100.0, Double(t.actualTransferred) / Double(total) * 100.0)
            }
        }

        func openHandleForAppend(atPath path: String) throws -> FileHandle {
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil, attributes: nil)
            }
            guard let handle = FileHandle(forWritingAtPath: path) else {
                throw WiredError(withTitle: "Download Error", message: "Cannot open destination file")
            }
            handle.seekToEndOfFile()
            return handle
        }

        var dataHandle: FileHandle?
        var rsrcHandle: FileHandle?
        defer {
            try? dataHandle?.close()
            try? rsrcHandle?.close()
        }

        while !(await isTerminating()) {
            if data && dataLength == 0 { data = false }
            if !data && rsrcLength == 0 { break }

            let oob = try tconn.socket.readOOB(timeout: 30.0)

            // Append data to appropriate fork
            if data {
                if dataHandle == nil {
                    dataHandle = try openHandleForAppend(atPath: tmpPath)
                }
                dataHandle?.write(oob)
            } else {
                if rsrcHandle == nil {
                    rsrcHandle = try openHandleForAppend(atPath: rsrcPath)
                }
                rsrcHandle?.write(oob)
            }

            // Update counters
            if data {
                pendingDataDelta += Int64(oob.count)
                dataLength = (dataLength > UInt64(oob.count)) ? (dataLength - UInt64(oob.count)) : 0
            } else {
                pendingRsrcDelta += Int64(oob.count)
                rsrcLength = (rsrcLength > UInt64(oob.count)) ? (rsrcLength - UInt64(oob.count)) : 0
            }

            fileTransferred += Int64(oob.count)

            pendingActualDelta += Int64(oob.count)
            speedBytes += oob.count

            time = TransfersTimeInterval()
            if time - speedTime > 0.33 {
                transfer.speedCalculator.add(bytes: speedBytes, time: (time - speedTime))
                pendingSpeed = transfer.speedCalculator.speed()
                speedBytes = 0
                speedTime = time
            }

            await flushProgress()

            // If we know expected size, allow early exit (per-file, not global)
            if expectedSize > 0 && fileTransferred >= expectedSize {
                break
            }
        }

        // Final speed update
        time = TransfersTimeInterval()
        transfer.speedCalculator.add(bytes: speedBytes, time: max(0.001, (time - speedTime)))
        pendingSpeed = transfer.speedCalculator.speed()
        await flushProgress(force: true)

        // Disconnect transfer connection for this file
        tconn.disconnect()

        if let term = await terminationReason() { throw term }

        // Move temp into final destination
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: localPath) {
            try? FileManager.default.removeItem(atPath: localPath)
        }
        try FileManager.default.moveItem(atPath: tmpPath, toPath: localPath)
    }

    // MARK: - Single file upload

    private func runUploadSingle(localPath: String, remotePath: String, expectedSize: Int64) async throws {
        let tconn = await ensureTransferConnection()
        tconn.interactive = false

        guard let url = transfer.connection?.url else {
            throw WiredError(withTitle: "Upload Error", message: "Missing connection URL")
        }

        try tconn.connect(withUrl: url, cipher: cipher, compression: compression, checksum: checksum)

        transfer.speedCalculator.add(bytes: 0, time: 0)
        await mutate { $0.speed = 0 }

        await mutate { $0.state = .waiting }

        // Send upload_file
        if !tconn.send(message: uploadFileMessage(remotePath: remotePath, totalSize: UInt64(max(expectedSize, 0)))) {
            throw WiredError(withTitle: "Upload Error", message: "Cannot send upload_file")
        }

        guard let ready = await waitForMessage(on: tconn, untilReceivingMessageName: "wired.transfer.upload_ready") else {
            if let term = await terminationReason() { throw term }
            throw WiredError(withTitle: "Upload Error", message: "Server did not reply upload_ready")
        }

        await mutate { $0.state = .running }

        let dataOffset = ready.uint64(forField: "wired.transfer.data_offset") ?? 0

        // Ensure persisted counters match server resume offset (single-file uploads).
        if !transfer.isFolder && dataOffset > 0 {
            await mutate {
                let o = Int64(dataOffset)
                if $0.dataTransferred < o { $0.dataTransferred = o }
                if $0.actualTransferred < o { $0.actualTransferred = o }
            }
        }
        var remaining = UInt64(max(expectedSize, 0))
        remaining = (remaining > dataOffset) ? (remaining - dataOffset) : 0

        // Now send upload (metadata)
        if !tconn.send(message: uploadMessage(remotePath: remotePath, dataLength: remaining, localPath: localPath)) {
            throw WiredError(withTitle: "Upload Error", message: "Cannot send upload")
        }

        let fileURL = URL(fileURLWithPath: localPath)
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        try fileHandle.seek(toOffset: dataOffset)

        var time = TransfersTimeInterval()
        var speedTime = TransfersTimeInterval()
        var speedBytes = 0
        var lastUIUpdate = TransfersTimeInterval()
        let uiUpdateInterval = 0.15

        var pendingDataDelta: Int64 = 0
        var pendingActualDelta: Int64 = 0
        var pendingSpeed: Double?

        func flushProgress(force: Bool = false) async {
            let now = TransfersTimeInterval()
            let hasPending = pendingDataDelta != 0 || pendingActualDelta != 0 || pendingSpeed != nil
            guard hasPending else { return }
            if !force && now - lastUIUpdate < uiUpdateInterval && pendingSpeed == nil {
                return
            }

            let dataDelta = pendingDataDelta
            let actualDelta = pendingActualDelta
            let speed = pendingSpeed

            pendingDataDelta = 0
            pendingActualDelta = 0
            pendingSpeed = nil
            lastUIUpdate = now

            await mutate { t in
                t.dataTransferred += dataDelta
                t.actualTransferred += actualDelta
                if let speed {
                    t.speed = speed
                }
                let total = max(t.size, 1)
                t.percent = min(100.0, Double(t.actualTransferred) / Double(total) * 100.0)
            }
        }

        while !(await isTerminating()) {
            if remaining == 0 { break }

            let chunk = try fileHandle.read(upToCount: 8192) ?? Data()
            if chunk.isEmpty {
                break
            }

            let sendBytes = min(UInt64(chunk.count), remaining)
            let toSend = (sendBytes == UInt64(chunk.count)) ? chunk : chunk.prefix(Int(sendBytes))

            try tconn.socket.writeOOB(data: Data(toSend), timeout: 30.0)

            remaining -= sendBytes

            pendingDataDelta += Int64(sendBytes)
            pendingActualDelta += Int64(sendBytes)
            speedBytes += Int(sendBytes)

            time = TransfersTimeInterval()
            if time - speedTime > 0.33 {
                transfer.speedCalculator.add(bytes: speedBytes, time: (time - speedTime))
                pendingSpeed = transfer.speedCalculator.speed()
                speedBytes = 0
                speedTime = time
            }

            await flushProgress()
        }

        time = TransfersTimeInterval()
        transfer.speedCalculator.add(bytes: speedBytes, time: max(0.001, (time - speedTime)))
        pendingSpeed = transfer.speedCalculator.speed()
        await flushProgress(force: true)

        tconn.disconnect()

        if let term = await terminationReason() { throw term }
    }

    // MARK: - Protocol helpers (queue, ping, errors)

    private func waitForMessage(on connection: TransferConnection, untilReceivingMessageName messageName: String) async -> P7Message? {
        while transfer.isWorking() || transfer.isTerminating() {
            let message: P7Message?
            do {
                message = try connection.readMessage()
            } catch {
                // timeout / disconnection
                return nil
            }

            guard let message else { continue }

            if message.name == messageName {
                return message
            }

            if message.name == "wired.transfer.queue" {
                let position = Int(message.uint32(forField: "wired.transfer.queue_position") ?? 0)
                await mutate { $0.queuePosition = position }
                if position > 0 {
                    await mutate { $0.state = .queued }
                } else if await readState() == .queued {
                    // slot acquired
                    await mutate { $0.state = .waiting }
                }
                continue
            }

            if message.name == "wired.transfer.send_ping" {
                // Correct behavior: reply with wired.ping, preserving transaction
                let reply = P7Message(withName: "wired.ping", spec: spec)
                if let t = message.uint32(forField: "wired.transaction") {
                    reply.addParameter(field: "wired.transaction", value: t)
                }
                _ = connection.send(message: reply)
                continue
            }

            if message.name == "wired.error" {
                if let error = connection.spec.error(forMessage: message) {
                    await mutate { $0.error = error.name ?? "wired.error" }
                } else {
                    await mutate { $0.error = "wired.error" }
                }
                return nil
            }
        }

        return nil
    }

    // MARK: - Remote directory listing (recursive)

    private func listRemoteDirectoryRecursive(path: String, connection: AsyncConnection) async throws -> [ListedEntry] {
        let message = P7Message(withName: "wired.file.list_directory", spec: spec)
        message.addParameter(field: "wired.file.path", value: path)
        message.addParameter(field: "wired.file.recursive", value: true)

        var results: [ListedEntry] = []

        for try await response in try connection.sendAndWaitMany(message) {
            guard response.name == "wired.file.file_list" else { continue }
            let filePath = response.string(forField: "wired.file.path") ?? ""
            let typeRaw = response.uint32(forField: "wired.file.type") ?? 0
            let type = FileType(rawValue: typeRaw) ?? .file
            let dataSize = response.uint64(forField: "wired.file.data_size") ?? 0
            let rsrcSize = response.uint64(forField: "wired.file.rsrc_size") ?? 0

            results.append(ListedEntry(path: filePath, type: type, dataSize: dataSize, rsrcSize: rsrcSize))
        }

        return results
    }

    private func uploadDirectory(remotePath: String, connection: AsyncConnection) async throws {
        let message = P7Message(withName: "wired.transfer.upload_directory", spec: spec)
        message.addParameter(field: "wired.file.path", value: remotePath)
        let response = try await connection.sendAsync(message)
        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }

    private func relativePath(full: String, root: String) -> String {
        if full == root { return "" }
        if full.hasPrefix(root) {
            var rel = String(full.dropFirst(root.count))
            rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return rel
        }
        return full
    }

    // MARK: - Messages

    private func downloadFileMessage(remotePath: String, dataOffset: UInt64, rsrcOffset: UInt64) -> P7Message {
        let message = P7Message(withName: "wired.transfer.download_file", spec: spec)
        message.addParameter(field: "wired.file.path", value: remotePath)
        message.addParameter(field: "wired.transfer.data_offset", value: dataOffset)
        message.addParameter(field: "wired.transfer.rsrc_offset", value: rsrcOffset)
        return message
    }

    private func uploadFileMessage(remotePath: String, totalSize: UInt64) -> P7Message {
        let message = P7Message(withName: "wired.transfer.upload_file", spec: spec)
        message.addParameter(field: "wired.file.path", value: remotePath)
        message.addParameter(field: "wired.transfer.data_size", value: totalSize)
        message.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))
        return message
    }

    private func uploadMessage(remotePath: String, dataLength: UInt64, localPath: String) -> P7Message {
        let finderInfo = FileManager.default.finderInfo(atPath: localPath) ?? Data(count: 32)

        let message = P7Message(withName: "wired.transfer.upload", spec: spec)
        message.addParameter(field: "wired.file.path", value: remotePath)
        message.addParameter(field: "wired.transfer.data", value: dataLength)
        message.addParameter(field: "wired.transfer.rsrc", value: UInt64(0))
        message.addParameter(field: "wired.transfer.finderinfo", value: finderInfo.base64EncodedData())
        return message
    }

    // MARK: - TransferConnection

    private func ensureTransferConnection() async -> TransferConnection {
        if let existing = await MainActor.run { self.transfer.transferConnection } {
            return existing
        }

        let connection = TransferConnection(withSpec: spec, transfer: transfer)
        if let nick = await MainActor.run { self.transfer.connection?.nick } {
            connection.nick = nick
        }
        if let status = await MainActor.run { self.transfer.connection?.status } {
            connection.status = status
        }
        if let icon = await MainActor.run { self.transfer.connection?.icon } {
            connection.icon = icon
        }
        await mutate { $0.transferConnection = connection }
        return connection
    }

// MARK: - Finish & timing

    // MARK: - Finish & timing

    private func finish(_ finalState: TransferState?) async {
        // Update accumulated time
        await mutate { t in
            if let started = t.startDate {
                t.accumulatedTime += Date().timeIntervalSince(started)
                t.startDate = nil
            }
        }

        // Disconnect and clear any per-transfer connection. When resuming transfers after an
        // app relaunch, this connection can be partially initialized; disconnect must be safe.
        if let tconn = await MainActor.run { self.transfer.transferConnection } {
            tconn.disconnect()
        }
        await mutate { $0.transferConnection = nil }

        if let finalState {
            await mutate { $0.state = finalState }
            return
        }

        // Preserve pause/stop intent
        let state = await readState()
        if state == .pausing || state == .paused {
            await mutate { $0.state = .paused }
        } else if state == .stopping || state == .stopped {
            await mutate { $0.state = .stopped }
        } else if state == .disconnecting {
            await mutate { $0.state = .disconnected }
        }
    }

    // MARK: - Local helpers

    /// Returns the size of the file at `path` in bytes, or `0` if the file does not exist.
    /// Used for resume support with partial files (".WiredTransfer").
    private func fileSize(atPath path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            if let n = attrs[.size] as? NSNumber { return n.int64Value }
            if let i = attrs[.size] as? Int { return Int64(i) }
            if let i = attrs[.size] as? Int64 { return i }
        } catch {
            // Ignore and treat as missing.
        }
        return 0
    }

    // MARK: - Destinations

    public static func temporaryDownloadDestination(forPath path: String) -> String {
        let root = UserDefaults.standard.string(forKey: "DownloadPath") ?? (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        let fileName = (path as NSString).lastPathComponent
        return (root as NSString).appendingPathComponent(fileName).appendingFormat(".%@", Wired.transfersFileExtension)
    }

    public static func defaultDownloadDestination(forPath path: String) -> String {
        let root = UserDefaults.standard.string(forKey: "DownloadPath") ?? (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        let fileName = (path as NSString).lastPathComponent
        return (root as NSString).appendingPathComponent(fileName)
    }

    private func temporaryDownloadDestination(forDestination dest: String) -> String {
        // Use the same partial extension as single downloads
        return dest.appendingFormat(".%@", Wired.transfersFileExtension)
    }
}
