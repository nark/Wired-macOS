//
//  TransferManager.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 11/01/2026.
//

import SwiftUI
import SwiftData
import WiredSwift

@MainActor
final class TransferManager: ObservableObject {
    enum DownloadQueueOutcome {
        case started(Transfer)
        case resumed(Transfer)
        case needsOverwrite(destination: String)
        case failed
    }

    @Published private(set) var transfers: [Transfer] = []

    /// WCTransfers.m model:
    /// - Queue enabled by default
    /// - Per connection (URI), allow 1 download + 1 upload simultaneously
    @Published var queueTransfersEnabled: Bool = true

    @AppStorage("DownloadPath") private var downloadPath: String = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")

    private let spec: P7Spec
    private let connectionController: ConnectionController

    /// SwiftData context used to persist transfers.
    private var modelContext: ModelContext?

    /// Running tasks keyed by transfer id.
    private var tasks: [UUID: Task<Void, Never>] = [:]

    private struct TransferSecurityOptions {
        let cipher: P7Socket.CipherType
        let compression: P7Socket.Compression
        let checksum: P7Socket.Checksum
    }

    init(spec: P7Spec, connectionController: ConnectionController) {
        self.spec = spec
        self.connectionController = connectionController
    }

    // MARK: - SwiftData wiring / persistence

    /// Call once when the SwiftData `ModelContext` is available.
    /// Restores persisted transfers and normalizes any in-flight state to `.paused`.
    func attach(modelContext: ModelContext) {
        // Idempotent
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext

        restorePersistedTransfers()
    }

    /// Pause and persist any in-flight transfers. Intended to be called when the app is terminating.
    func prepareForTermination() {
        for t in transfers {
            if t.isWorking() {
                t.state = .paused
                t.speed = 0
                t.queuePosition = 0
            }
        }
        persist()
    }

    private func restorePersistedTransfers() {
        guard let modelContext else { return }

        do {
            let descriptor = FetchDescriptor<Transfer>(sortBy: [SortDescriptor(\Transfer.createdDate, order: .forward)])
            let persisted = try modelContext.fetch(descriptor)

            // Adopt persisted list.
            self.transfers = persisted

            // WCTransfers behavior: on relaunch, anything that was not finished becomes paused.
            for t in persisted {
                if t.state != .finished {
                    if t.isWorking() || t.isTerminating() || t.state == .locallyQueued || t.state == .queued {
                        t.state = .paused
                        t.speed = 0
                        t.queuePosition = 0
                    }
                }

                // Never restore live connections.
                t.connection = nil
                t.transferConnection = nil
                t.speedCalculator = SpeedCalculator()
            }

            persist()
        } catch {
            // If restore fails, keep the in-memory list empty.
            print("[TransferManager] restore failed:", error)
        }
    }

    private func persist() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
        } catch {
            print("[TransferManager] save failed:", error)
        }
    }

    // MARK: - Public API

    /// Remove finished transfers from the list.
    func clear() {
        let finishedTransfers = transfers.filter { $0.state == .finished }
        transfers.removeAll { $0.state == .finished }

        if let modelContext {
            for transfer in finishedTransfers {
                modelContext.delete(transfer)
            }
        }

        persist()
    }

    func download(_ file: FileItem, with connectionID: UUID) {
        let destination: String

        let isFolder = (file.type == .directory || file.type == .uploads || file.type == .dropbox)
        if isFolder {
            // Download folders into Downloads/<foldername>
            destination = (downloadPath as NSString).appendingPathComponent(file.name)
        } else {
            destination = (downloadPath as NSString).appendingPathComponent(file.name)
        }

        _ = download(file, to: destination, with: connectionID)
    }

    @discardableResult
    func download(_ file: FileItem, to destination: String, with connectionID: UUID) -> Bool {
        downloadTransfer(file, to: destination, with: connectionID) != nil
    }

    @discardableResult
    func queueDownload(_ file: FileItem, with connectionID: UUID, overwriteExistingFile: Bool) -> DownloadQueueOutcome {
        let destination = (downloadPath as NSString).appendingPathComponent(file.name)
        return queueDownload(file, to: destination, with: connectionID, overwriteExistingFile: overwriteExistingFile)
    }

    @discardableResult
    func queueDownload(_ file: FileItem, to destination: String, with connectionID: UUID, overwriteExistingFile: Bool) -> DownloadQueueOutcome {
        let requestedFinalDestination = normalizedFinalDestination(for: destination)
        let finalDestination = canonicalResumeFinalDestination(
            requestedFinalDestination: requestedFinalDestination,
            expectedName: file.name,
            remotePath: file.path,
            connectionID: connectionID
        )
        let partialDestination = finalDestination.appendingFormat(".%@", Wired.transfersFileExtension)
        let partialExists = FileManager.default.fileExists(atPath: partialDestination)
        let finalExists = FileManager.default.fileExists(atPath: finalDestination)
        let existing = existingDownloadTransfer(
            remotePath: file.path,
            connectionID: connectionID,
            finalDestination: finalDestination
        )

        if let existing, isActivelyProcessing(existing) {
            return .resumed(existing)
        }

        // Resume has priority when a partial ".WiredTransfer" exists.
        if partialExists {
            if let existing {
                restartForDownload(existing, resetProgress: false)
                return .resumed(existing)
            }
            guard let transfer = downloadTransfer(file, to: finalDestination, with: connectionID) else {
                return .failed
            }
            return .started(transfer)
        }

        // No partial file: if final destination exists, user must choose overwrite/stop.
        if finalExists && !overwriteExistingFile {
            return .needsOverwrite(destination: finalDestination)
        }

        // Reuse a previous transfer record when possible, but restart from scratch.
        if let existing {
            restartForDownload(existing, resetProgress: true)
            return .resumed(existing)
        }

        guard let transfer = downloadTransfer(file, to: finalDestination, with: connectionID) else {
            return .failed
        }
        return .started(transfer)
    }

    private func isActivelyProcessing(_ transfer: Transfer) -> Bool {
        transfer.isWorking() || transfer.state == .locallyQueued || transfer.state == .queued
    }

    private func restartForDownload(_ transfer: Transfer, resetProgress: Bool) {
        if resetProgress {
            transfer.dataTransferred = 0
            transfer.rsrcTransferred = 0
            transfer.actualTransferred = 0
            transfer.percent = 0
            transfer.speed = 0
            transfer.error = ""
        }
        if transfer.state != .locallyQueued {
            transfer.state = .locallyQueued
        }
        persist()
        if let uri = transfer.uri {
            requestNextTransfer(forURI: uri)
        } else {
            start(transfer)
        }
    }

    @discardableResult
    func downloadTransfer(_ file: FileItem, to destination: String, with connectionID: UUID) -> Transfer? {
        guard let runtime = connectionController.runtime(for: connectionID) else { return nil }
        guard let connection = runtime.connection as? AsyncConnection else { return nil }

        let transfer = Transfer(name: file.name, type: .download, connection: connection)
        transfer.uri = connection.URI
        transfer.connectionID = connectionID
        transfer.remotePath = file.path
        transfer.localPath = destination
        transfer.file = file
        transfer.isFolder = (file.type == .directory || file.type == .uploads || file.type == .dropbox)

        // For folders, size/progress will be computed during listing.
        if !transfer.isFolder {
            transfer.size = Int64(file.dataSize + file.rsrcSize)
            transfer.totalFiles = 1
        } else {
            transfer.size = 0
            transfer.totalFiles = 0
        }

        addTransfer(transfer)
        return transfer
    }

    @discardableResult
    func upload(
        _ path: String,
        toDirectory destination: FileItem,
        with connectionID: UUID,
        filesViewModel: FilesViewModel? = nil
    ) -> Bool {
        uploadTransfer(path, toDirectory: destination, with: connectionID, filesViewModel: filesViewModel) != nil
    }

    @discardableResult
    func uploadTransfer(
        _ path: String,
        toDirectory destination: FileItem,
        with connectionID: UUID,
        filesViewModel: FilesViewModel? = nil
    ) -> Transfer? {
        guard let runtime = connectionController.runtime(for: connectionID) else { return nil }
        guard let connection = runtime.connection as? AsyncConnection else { return nil }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

        // Remote target path for uploads:
        // destination.path/<local name>
        let remotePath = destination.path.stringByAppendingPathComponent(path: path.lastPathComponent)

        let transfer = Transfer(name: path.lastPathComponent, type: .upload, connection: connection)
        transfer.uri = connection.URI
        transfer.connectionID = connectionID
        transfer.remotePath = remotePath
        transfer.localPath = path
        transfer.isFolder = isDir.boolValue

        if transfer.isFolder {
            // Folder upload: size & file list computed in worker.
            transfer.size = 0
            transfer.totalFiles = 0
        } else {
            var file = FileItem(path.lastPathComponent, path: remotePath)
            file.uploadDataSize = FileManager.sizeOfFile(atPath: path) ?? 0
            transfer.file = file
            transfer.size = Int64(file.uploadDataSize + file.uploadRsrcSize)
            transfer.totalFiles = 1
        }

        addTransfer(transfer)

        // Optional refresh when done (kept compatible with your PoC).
        if let filesViewModel {
            // Register a small post-finish hook.
            transfer.error = transfer.error // keep SwiftData aware
            onTransferFinished(id: transfer.id) { [weak filesViewModel] in
                guard let filesViewModel else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                await filesViewModel.reloadSelectedColumn()
            }
        }

        return transfer
    }

    func start(_ transfer: Transfer) {
        guard let uri = transfer.uri else { return }

        switch transfer.state {
        case .locallyQueued, .paused, .stopped, .disconnected:
            // Move back to local queue and let the scheduler decide.
            transfer.state = .locallyQueued
            persist()
            requestNextTransfer(forURI: uri)
        default:
            break
        }
    }

    func pause(_ transfer: Transfer) {
        guard let uri = transfer.uri else { return }

        if transfer.state == .locallyQueued {
            transfer.state = .paused
            persist()
            return
        }

        transfer.state = .pausing
        persist()
        // Worker will switch to .paused and disconnect.
        // When it does, we schedule the next transfer.
        requestNextTransfer(forURI: uri)
    }

    func stop(_ transfer: Transfer) {
        guard let uri = transfer.uri else { return }

        if transfer.state == .locallyQueued {
            transfer.state = .stopped
            persist()
            return
        }

        transfer.state = .stopping
        persist()
        requestNextTransfer(forURI: uri)
    }

    func remove(_ transfer: Transfer) {
        guard let uri = transfer.uri else {
            transfers.removeAll { $0.id == transfer.id }
            if let modelContext {
                modelContext.delete(transfer)
            }
            persist()
            return
        }

        if transfer.isWorking() {
            transfer.state = .removing
            persist()
            // Worker will disconnect and mark stopped/finished depending.
        } else {
            transfers.removeAll { $0.id == transfer.id }
            if let modelContext {
                modelContext.delete(transfer)
            }
            persist()
        }

        requestNextTransfer(forURI: uri)
    }

    // MARK: - Internal scheduling (WCTransfers-like)

    private func addTransfer(_ transfer: Transfer) {
        // WCTransfers: if queue enabled and we already have a working transfer of the same
        // class (download/upload) for this connection, we locally queue it.
        transfers.append(transfer)
        if let modelContext {
            modelContext.insert(transfer)
            persist()
        }

        guard let uri = transfer.uri else {
            transfer.state = .locallyQueued
            persist()
            return
        }

        let workingCountSameType = numberOfWorkingTransfers(type: transfer.type, uri: uri)

        if queueTransfersEnabled && workingCountSameType > 0 {
            transfer.state = .locallyQueued
            persist()
        } else {
            requestTransfer(transfer)
        }

        requestNextTransfer(forURI: uri)
    }

    private func requestNextTransfer(forURI uri: String) {
        // Equivalent of WCTransfers _requestNextTransferForConnection:
        // When queue is enabled, allow:
        //  - 1 download and 1 upload simultaneously per connection.

        // If something is already starting (waiting/queued/listing/running), do not start a second of same type.
        let downloads = numberOfWorkingTransfers(type: .download, uri: uri)
        let uploads = numberOfWorkingTransfers(type: .upload, uri: uri)

        var next: Transfer? = nil

        if !queueTransfersEnabled {
            next = firstTransfer(state: .locallyQueued, uri: uri)
        } else {
            if downloads == 0 && uploads == 0 {
                next = firstTransfer(state: .locallyQueued, uri: uri)
            } else if downloads == 0 {
                next = firstTransfer(state: .locallyQueued, uri: uri, type: .download)
            } else if uploads == 0 {
                next = firstTransfer(state: .locallyQueued, uri: uri, type: .upload)
            }
        }

        if let next {
            requestTransfer(next)
        }
    }

    private func normalizedFinalDestination(for destination: String) -> String {
        if (destination as NSString).pathExtension.caseInsensitiveCompare(Wired.transfersFileExtension) == .orderedSame {
            return (destination as NSString).deletingPathExtension
        }
        return destination
    }

    /// Finder can disambiguate promised filenames by appending " 2", " 3", …
    /// after the original full file name (e.g. "name.dmg 2.WiredTransfer").
    /// If an original partial already exists, force resume on that canonical path.
    private func canonicalResumeFinalDestination(
        requestedFinalDestination: String,
        expectedName: String,
        remotePath: String,
        connectionID: UUID
    ) -> String {
        let requestedURL = URL(fileURLWithPath: requestedFinalDestination)
        let requestedName = requestedURL.lastPathComponent

        guard let range = requestedName.range(of: #" \d+$"#, options: .regularExpression) else {
            return requestedFinalDestination
        }

        let strippedName = String(requestedName[..<range.lowerBound])
        guard strippedName == expectedName else {
            return requestedFinalDestination
        }

        let canonicalURL = requestedURL.deletingLastPathComponent().appendingPathComponent(strippedName, isDirectory: false)
        let canonicalPartial = canonicalURL.path.appendingFormat(".%@", Wired.transfersFileExtension)
        let canonicalFinal = canonicalURL.path

        if FileManager.default.fileExists(atPath: canonicalFinal) {
            return canonicalFinal
        }
        if FileManager.default.fileExists(atPath: canonicalPartial) {
            return canonicalFinal
        }

        if existingDownloadTransfer(
            remotePath: remotePath,
            connectionID: connectionID,
            finalDestination: canonicalFinal
        ) != nil {
            return canonicalFinal
        }

        return requestedFinalDestination
    }

    private func existingDownloadTransfer(remotePath: String, connectionID: UUID, finalDestination: String) -> Transfer? {
        transfers.first { transfer in
            guard transfer.type == .download else { return false }
            guard transfer.connectionID == connectionID else { return false }
            guard transfer.remotePath == remotePath else { return false }
            guard transfer.state != .finished && transfer.state != .removing else { return false }
            let local = transfer.localPath ?? ""
            return normalizedFinalDestination(for: local) == finalDestination
        }
    }

    private func requestTransfer(_ transfer: Transfer) {
        // Avoid starting twice
        if tasks[transfer.id] != nil { return }

        // Transfers are persisted without their live connection. Re-resolve it on demand.
        if transfer.connection == nil {
            if let cid = transfer.connectionID,
               let runtime = connectionController.runtime(for: cid),
               let conn = runtime.connection as? AsyncConnection {
                transfer.connection = conn
                transfer.uri = conn.URI
            } else {
                transfer.error = "No active connection for this transfer. Please reconnect."
                transfer.state = .disconnected
                persist()
                return
            }
        }

        transfer.startDate = Date()
        transfer.speed = 0
        transfer.percent = 0
        transfer.queuePosition = 0

        if !transfer.isTerminating() {
            transfer.state = .waiting
        }

        persist()

        let id = transfer.id
        let downloadRoot = self.downloadPath
        let security = transferSecurityOptions(for: transfer.connectionID)

        let t = Task.detached(priority: .userInitiated) { [spec] in
            let worker = await TransferWorker(
                transfer: transfer,
                spec: spec,
                downloadRoot: downloadRoot,
                cipher: security.cipher,
                compression: security.compression,
                checksum: security.checksum
            )
            await worker.run()

            await MainActor.run {
                // Task finished: free slot + schedule next
                self.tasks[id] = nil
                self.runTerminalHookIfNeeded(for: transfer)
                self.runFinishHookIfNeeded(for: transfer)
                self.persist()
                if let uri = transfer.uri {
                    self.requestNextTransfer(forURI: uri)
                }
            }
        }

        tasks[transfer.id] = t
    }

    private func transferSecurityOptions(for connectionID: UUID?) -> TransferSecurityOptions {
        let defaults = TransferSecurityOptions(
            cipher: .ECDH_CHACHA20_POLY1305,
            compression: .DEFLATE,
            checksum: .HMAC_256
        )

        guard let modelContext, let connectionID else {
            return defaults
        }

        do {
            var descriptor = FetchDescriptor<Bookmark>(
                predicate: #Predicate { bookmark in
                    bookmark.id == connectionID
                }
            )
            descriptor.fetchLimit = 1

            guard let bookmark = try modelContext.fetch(descriptor).first else {
                return defaults
            }

            return TransferSecurityOptions(
                cipher: bookmark.cipher,
                compression: bookmark.compression,
                checksum: bookmark.checksum
            )
        } catch {
            return defaults
        }
    }

    private func numberOfWorkingTransfers(type: TransferType, uri: String) -> Int {
        transfers.filter { t in
            guard t.uri == uri, t.type == type else { return false }
            // For scheduling, treat terminating states as still "working" until they reach a stable end state.
            if t.state == .locallyQueued { return false }
            if t.state == .paused || t.state == .stopped || t.state == .disconnected || t.state == .finished { return false }
            return true
        }.count
    }

    private func firstTransfer(state: TransferState, uri: String, type: TransferType? = nil) -> Transfer? {
        transfers.first {
            $0.uri == uri && $0.state == state && (type == nil || $0.type == type)
        }
    }

    // MARK: - Optional post-finish hooks

    private var finishHooks: [UUID: () async -> Void] = [:]
    private var terminalHooks: [UUID: (Transfer) -> Void] = [:]

    private func onTransferFinished(id: UUID, _ hook: @escaping () async -> Void) {
        finishHooks[id] = hook
    }

    func onTransferTerminal(id: UUID, _ hook: @escaping (Transfer) -> Void) {
        terminalHooks[id] = hook
    }

    /// Called by the UI or worker when a transfer moved to `.finished`.
    func runFinishHookIfNeeded(for transfer: Transfer) {
        guard transfer.state == .finished else { return }
        guard let hook = finishHooks.removeValue(forKey: transfer.id) else { return }
        Task { await hook() }
    }

    private func runTerminalHookIfNeeded(for transfer: Transfer) {
        let isTerminal = (
            transfer.state == .finished ||
            transfer.state == .stopped ||
            transfer.state == .paused ||
            transfer.state == .disconnected
        )
        guard isTerminal else { return }
        guard let hook = terminalHooks.removeValue(forKey: transfer.id) else { return }
        hook(transfer)
    }
}
