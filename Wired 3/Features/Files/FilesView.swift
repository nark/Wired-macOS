//
//  FilesView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 09/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift
import UniformTypeIdentifiers
import CoreTransferable
#if os(macOS)
import AppKit
import ObjectiveC
import Darwin
import SQLite3
#endif

struct FilesView: View {
    struct UploadConflict: Identifiable {
        let id = UUID()
        let localPath: String
        let remotePath: String
    }

    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @EnvironmentObject var transfers: TransferManager

    let connectionID: UUID
    @AppStorage("filesPreferredViewType") private var preferredFileViewTypeRawValue: Int = FileViewType.columns.rawValue
    @AppStorage("filesTreeSortColumn") private var treeSortColumn: String = "name"
    @AppStorage("filesTreeSortAscending") private var treeSortAscending = true

    @ObservedObject var filesViewModel: FilesViewModel

    @State var pendingDeleteItems: [FileItem] = []
    @State var showDeleteSelectionConfirmation: Bool = false
    @State var createFolderTargetOverride: FileItem?
    @State var pendingDownloadItems: [FileItem] = []
    @State var pendingUploadConflicts: [UploadConflict] = []
    @State var activeUploadConflict: UploadConflict?
    @State var infoSheetItem: FileItem?
    @State var primarySelectionPath: String?
    @State var selectedItemsForToolbar: [FileItem] = []
    @State var backDirectoryHistory: [String] = []
    @State var forwardDirectoryHistory: [String] = []
    @State var currentDirectoryPath: String = "/"
    @State var isApplyingHistoryNavigation: Bool = false
    @State private var syncActivationNotice: SyncActivationNotice?
    @State private var pendingDeactivateSyncDirectory: FileItem?
    @State private var showDeactivateSyncConfirmation: Bool = false
    @State private var pairedSyncRemotePaths: Set<String> = []
    @State private var pairedSyncDescriptors: Set<WiredSyncPairDescriptor> = []
    @State private var syncPairLocalOverrides: [String: SyncPairLocalOverride] = [:]
    @State private var syncPairModeReconciliationInFlight: Set<String> = []
    @State private var isSyncPairStatusRefreshing: Bool = false
    @State private var syncPairStatusRefreshToken: UUID?
    @State private var lastSyncPairStatusRefreshAt: Date = .distantPast
    @State private var syncPairStatusRefreshTask: Task<Void, Never>?
    @State private var syncPairPollingTask: Task<Void, Never>?
    @State private var syncPairStatusVersion: Int = 0
    @State private var selectedSyncStatusPath: String?

    @State var currentSearchTask: Task<Void, Never>?

    private var preferredFileViewType: FileViewType {
        get { FileViewType(rawValue: preferredFileViewTypeRawValue) ?? .columns }
        nonmutating set { preferredFileViewTypeRawValue = newValue.rawValue }
    }

    var selectedItem: FileItem? {
        switch filesViewModel.selectedFileViewType {
        case .columns:
            guard let primarySelectionPath else { return nil }
            return itemForPath(primarySelectionPath)
        case .tree:
            if let primarySelectionPath,
               let item = itemForPath(primarySelectionPath) {
                return item
            }
            return filesViewModel.selectedTreeItem()
        }
    }

    var canGoBack: Bool {
        !backDirectoryHistory.isEmpty
    }

    var canGoForward: Bool {
        !forwardDirectoryHistory.isEmpty
    }

    var breadcrumbPath: String {
        switch filesViewModel.selectedFileViewType {
        case .columns:
            return primarySelectionPath
                ?? filesViewModel.selectedItem?.path
                ?? filesViewModel.columns.last?.path
                ?? currentDirectoryPath
        case .tree:
            return primarySelectionPath
                ?? filesViewModel.treeSelectionPath
                ?? filesViewModel.treeRootPath
        }
    }

    func itemForPath(_ path: String) -> FileItem? {
        if let item = filesViewModel.columns
            .flatMap(\.items)
            .first(where: { $0.path == path }) {
            return item
        }

        if let item = filesViewModel.visibleTreeNodes()
            .map(\.item)
            .first(where: { $0.path == path }) {
            return item
        }

        if path == "/" || path == filesViewModel.treeRootPath {
            let name = path == "/" ? "/" : (path as NSString).lastPathComponent
            return FileItem(name, path: path, type: .directory)
        }

        return nil
    }

    var selectedDirectoryForUpload: FileItem? {
        if let override = createFolderTargetOverride {
            return override
        }

        var selected: FileItem
        switch filesViewModel.selectedFileViewType {
        case .columns:
            if let lastColumn = filesViewModel.columns.last,
               let selectedID = lastColumn.selection,
               let selectedItem = lastColumn.items.first(where: { $0.id == selectedID }) {
                selected = selectedItem
            } else if let selectedItem {
                selected = selectedItem
            } else {
                return nil
            }
        case .tree:
            guard let selectedItem else { return nil }
            selected = selectedItem
        }

        if selected.type.isDirectoryLike {
            return selected
        }

        let parentPath = normalizedRemotePath(selected.path.stringByDeletingLastPathComponent)
        if let parentItem = itemForPath(parentPath), parentItem.type.isDirectoryLike {
            return parentItem
        }
        return FileItem(parentPath.lastPathComponent, path: parentPath, type: .directory)
    }

    private var selectedSyncDirectory: FileItem? {
        if let target = selectedDirectoryForUpload {
            if target.type == .sync {
                return target
            }
            if let resolved = itemForPath(target.path), resolved.type == .sync {
                return resolved
            }
        }

        if let path = primarySelectionPath,
           let directoryPath = directoryPath(from: path),
           let directoryItem = itemForPath(directoryPath),
           directoryItem.type == .sync {
            return directoryItem
        }

        return nil
    }

    private func syncDirectoryPath(for primaryPath: String?) -> String? {
        guard let primaryPath else { return nil }
        if let item = itemForPath(primaryPath) {
            if item.type == .sync {
                return normalizeSyncRemotePath(item.path)
            }
            let parentPath = normalizedRemotePath(item.path.stringByDeletingLastPathComponent)
            if let parent = itemForPath(parentPath), parent.type == .sync {
                return normalizeSyncRemotePath(parent.path)
            }
        }
        return nil
    }

    func updatePrimarySelectionPath(_ path: String?) {
        primarySelectionPath = path
        if let syncPath = syncDirectoryPath(for: path) {
            selectedSyncStatusPath = syncPath
        } else if path != nil {
            selectedSyncStatusPath = nil
        }
    }

    private func bumpSyncPairStatusVersion() {
        syncPairStatusVersion &+= 1
    }

    private var currentSyncServerURL: String? {
        guard let connection = runtime.connection as? AsyncConnection,
              let url = connection.url else {
            return nil
        }
        return "\(url.hostname):\(url.port)"
    }

    private var currentSyncLogin: String? {
        guard let connection = runtime.connection as? AsyncConnection,
              let url = connection.url else {
            return nil
        }
        return url.login.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleSyncItems() -> [FileItem] {
        let items = filesViewModel.columns.flatMap(\.items) + filesViewModel.visibleTreeNodes().map(\.item)
        var seen: Set<String> = []
        return items.filter { item in
            guard item.type == .sync else { return false }
            let path = normalizeSyncRemotePath(item.path)
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private func effectiveSyncMode(for item: FileItem) -> String? {
        guard item.type == .sync else { return nil }
        if item.syncEffectiveMode == .disabled {
            return nil
        }
        return item.syncEffectiveMode.rawValue
    }

    private func shouldEnableRemoteDelete(for item: FileItem) -> Bool {
        guard item.type == .sync else { return false }
        guard runtime.hasPrivilege("wired.account.file.sync.delete_remote") else { return false }
        switch item.syncEffectiveMode {
        case .clientToServer, .bidirectional:
            return true
        case .disabled, .serverToClient:
            return false
        }
    }

    private func reconcileSyncPairModesIfNeeded(descriptors: Set<WiredSyncPairDescriptor>) {
        guard let serverURL = currentSyncServerURL,
              let login = currentSyncLogin else { return }

        let visibleItems = visibleSyncItems()
        for item in visibleItems {
            let path = normalizeSyncRemotePath(item.path)
            guard pairedSyncRemotePaths.contains(path) else { continue }
            guard let expectedMode = effectiveSyncMode(for: item) else { continue }
            guard let descriptor = descriptors.first(where: {
                $0.remotePath == path && $0.serverURL == serverURL && $0.login == login
            }) else { continue }
            let expectedDeleteRemote = shouldEnableRemoteDelete(for: item)
            let expectedExcludePatterns = item.syncExcludePatterns
            guard descriptor.mode != expectedMode || descriptor.deleteRemoteEnabled != expectedDeleteRemote else { continue }
            guard !syncPairModeReconciliationInFlight.contains(path) else { continue }

            syncPairModeReconciliationInFlight.insert(path)
            print("[WiredSyncUI] reconcile.mode remote=\(path) stored=\(descriptor.mode) effective=\(expectedMode) delete_remote=\(expectedDeleteRemote)")

            Task.detached(priority: .utility) {
                do {
                    let updatedCount = try WiredSyncDaemonIPC.updatePairPolicy(
                        remotePath: path,
                        mode: expectedMode,
                        deleteRemoteEnabled: expectedDeleteRemote,
                        excludePatterns: expectedExcludePatterns,
                        serverURL: serverURL,
                        login: login
                    )
                    await MainActor.run {
                        syncPairModeReconciliationInFlight.remove(path)
                        print("[WiredSyncUI] reconcile.mode.success remote=\(path) updated=\(updatedCount) mode=\(expectedMode)")
                        scheduleSyncPairStatusRefresh(delayNanoseconds: 500_000_000, force: true, showProgress: false)
                    }
                } catch {
                    await MainActor.run {
                        syncPairModeReconciliationInFlight.remove(path)
                        print("[WiredSyncUI] reconcile.mode.error remote=\(path) error=\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func debugLogSyncStatuses(context: String, livePaths: Set<String>? = nil, persistedPaths: Set<String>? = nil) {
        let endpoint = currentSyncServerURL ?? "<none>"
        let login = (currentSyncLogin?.isEmpty == false ? currentSyncLogin! : "<none>")
        let visible = visibleSyncItems()
        let visiblePaths = visible.map { normalizeSyncRemotePath($0.path) }.sorted()
        print("[WiredSyncUI] context=\(context) endpoint=\(endpoint) login=\(login) visible=\(visiblePaths)")
        if let livePaths {
            print("[WiredSyncUI] context=\(context) live_paths=\(Array(livePaths).sorted())")
        }
        if let persistedPaths {
            print("[WiredSyncUI] context=\(context) persisted_paths=\(Array(persistedPaths).sorted())")
        }
        for item in visible.sorted(by: { $0.path < $1.path }) {
            let path = normalizeSyncRemotePath(item.path)
            let overrideDescription: String
            if let override = syncPairLocalOverrides[path] {
                switch override {
                case .checking(let active):
                    overrideDescription = "checking(\(active ? "active" : "inactive"))"
                case .sticky(let active, let until):
                    overrideDescription = "sticky(\(active ? "active" : "inactive"),until=\(until.timeIntervalSince1970))"
                }
            } else {
                overrideDescription = "none"
            }
            print(
                "[WiredSyncUI] item=\(path) status=\(String(describing: syncPairStatus(for: item))) " +
                "exists=\(syncPairExists(for: item)) paired=\(pairedSyncRemotePaths.contains(path)) override=\(overrideDescription)"
            )
        }
    }

    private func setSyncPairLocalOverride(_ override: SyncPairLocalOverride?, for path: String) {
        let normalizedPath = normalizeSyncRemotePath(path)
        if let override {
            syncPairLocalOverrides[normalizedPath] = override
        } else {
            syncPairLocalOverrides.removeValue(forKey: normalizedPath)
        }
        bumpSyncPairStatusVersion()
    }

    private func syncPairDescriptor(for path: String) -> WiredSyncPairDescriptor? {
        let normalizedPath = normalizeSyncRemotePath(path)
        let serverURL = currentSyncServerURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = currentSyncLogin?.trimmingCharacters(in: .whitespacesAndNewlines)
        return pairedSyncDescriptors.first(where: { descriptor in
            descriptor.remotePath == normalizedPath &&
                (serverURL == nil || serverURL?.isEmpty == true || descriptor.serverURL == serverURL) &&
                (login == nil || login?.isEmpty == true || descriptor.login == login)
        })
    }

    private func syncPairStatus(for item: FileItem) -> SyncPairStatusDisplay {
        guard item.type == .sync else { return .hidden }
        let path = normalizeSyncRemotePath(item.path)
        if let override = syncPairLocalOverrides[path] {
            switch override {
            case .checking:
                return .checking
            case .sticky(let active, let until):
                if until > Date() {
                    return active ? .connected : .inactive
                }
            }
        }
        guard pairedSyncRemotePaths.contains(path) else { return .inactive }
        guard let descriptor = syncPairDescriptor(for: path) else { return .connected }
        if descriptor.paused || descriptor.runtimeState == .paused {
            return .paused
        }
        switch descriptor.runtimeState {
        case .connecting:
            return .connecting
        case .connected, .disconnected, nil:
            return .connected
        case .syncing:
            return .syncing
        case .reconnecting:
            return .reconnecting
        case .error:
            return .error(message: descriptor.runtimeLastError)
        case .paused:
            return .paused
        }
    }

    private func syncPairExists(for item: FileItem) -> Bool {
        guard item.type == .sync else { return false }
        let path = normalizeSyncRemotePath(item.path)
        if let override = syncPairLocalOverrides[path] {
            switch override {
            case .checking(let active):
                return active
            case .sticky(let active, let until):
                if until > Date() {
                    return active
                }
            }
        }
        return pairedSyncRemotePaths.contains(path)
    }

    var selectedDownloadableItem: FileItem? {
        guard let selectedItem, canDownload(item: selectedItem) else { return nil }
        return selectedItem
    }

    var selectedDeletableItem: FileItem? {
        guard let selectedItem, canDelete(item: selectedItem) else { return nil }
        return selectedItem
    }

    var selectedDeletableItems: [FileItem] {
        let source = selectedItemsForToolbar.isEmpty ? [selectedItem].compactMap { $0 } : selectedItemsForToolbar
        return uniqueItems(source).filter { canDelete(item: $0) }
    }

    var canSetFileType: Bool {
        runtime.hasPrivilege("wired.account.file.set_type")
    }

    private func canWriteDropbox(_ item: FileItem) -> Bool {
        !item.type.isManagedAccessType || item.writable
    }

    private func canReadDropbox(_ item: FileItem) -> Bool {
        !item.type.isManagedAccessType || item.readable
    }

    func canDownload(item: FileItem) -> Bool {
        runtime.hasPrivilege("wired.account.transfer.download_files")
        && isDownloadableRemoteItem(item)
        && canReadDropbox(item)
    }

    func canDelete(item: FileItem) -> Bool {
        guard item.path != "/" else { return false }
        if item.type == .sync {
            return item.writable
        }
        if item.type == .dropbox {
            return item.readable && item.writable
        }
        return runtime.hasPrivilege("wired.account.file.delete_files")
    }

    func canUpload(to directory: FileItem) -> Bool {
        guard directory.type.isDirectoryLike else { return false }

        let canUploadFiles = runtime.hasPrivilege("wired.account.transfer.upload_files")
        let canUploadDirectories = runtime.hasPrivilege("wired.account.transfer.upload_directories")
        guard canUploadFiles || canUploadDirectories else { return false }

        if directory.type.isManagedAccessType {
            return directory.writable
        }

        if directory.type == .directory {
            return runtime.hasPrivilege("wired.account.transfer.upload_anywhere")
        }

        return true
    }

    func canCreateFolder(in directory: FileItem) -> Bool {
        guard directory.type.isDirectoryLike else { return false }
        if directory.type.isManagedAccessType {
            return directory.writable
        }
        return runtime.hasPrivilege("wired.account.file.create_directories")
    }

    func canDropRemoteItem(from sourcePath: String, to destinationDirectory: FileItem, link: Bool) -> Bool {
        guard destinationDirectory.type.isDirectoryLike else { return false }
        guard sourcePath != "/", let sourceItem = itemForPath(sourcePath) else { return false }

        let requiredPrivilege = link ? "wired.account.file.create_links" : "wired.account.file.move_files"
        let sourceAllowed: Bool

        if sourceItem.type.isManagedAccessType {
            sourceAllowed = link ? sourceItem.readable : sourceItem.writable
        } else {
            sourceAllowed = runtime.hasPrivilege(requiredPrivilege)
        }

        guard sourceAllowed else { return false }

        if destinationDirectory.type.isManagedAccessType {
            return destinationDirectory.writable
        }

        return runtime.hasPrivilege(requiredPrivilege)
    }

    func canGetInfo(for item: FileItem) -> Bool {
        guard runtime.hasPrivilege("wired.account.file.get_info") else { return false }
        guard item.type.isManagedAccessType else { return true }
        if item.type == .sync && runtime.hasPrivilege("wired.account.file.set_permissions") {
            return true
        }
        return item.readable
    }

    private func activateSync(for directory: FileItem) {
#if os(macOS)
        guard runtime.hasPrivilege("wired.account.file.sync.sync_files") else {
            syncActivationNotice = SyncActivationNotice(
                title: "Sync Error",
                message: "Your account is not allowed to activate sync pairs."
            )
            return
        }

        guard let connection = runtime.connection as? AsyncConnection,
              let url = connection.url else {
            syncActivationNotice = SyncActivationNotice(
                title: "Sync Error",
                message: "No active Wired connection available for sync activation."
            )
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Select the local folder paired with \(directory.path)"

        guard panel.runModal() == .OK, let localURL = panel.url else { return }

        let currentDirectory = filesViewModel.currentItem(path: directory.path) ?? directory
        guard let mode = effectiveSyncMode(for: currentDirectory) else {
            syncActivationNotice = SyncActivationNotice(
                title: "Sync Error",
                message: "The selected sync folder is disabled for your account."
            )
            return
        }
        let serverURL = "\(url.hostname):\(url.port)"
        let login = url.login.trimmingCharacters(in: .whitespacesAndNewlines)
        let deleteRemoteEnabled = shouldEnableRemoteDelete(for: currentDirectory)

        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                setSyncPairLocalOverride(.checking(active: true), for: directory.path)
                print("[WiredSyncUI] activate path=\(directory.path) sync_mode=\(mode) delete_remote=\(deleteRemoteEnabled)")
            }
            do {
                _ = try WiredSyncDaemonIPC.addPair(
                    remotePath: directory.path,
                    localPath: localURL.path,
                    mode: mode,
                    deleteRemoteEnabled: deleteRemoteEnabled,
                    excludePatterns: directory.syncExcludePatterns,
                    serverURL: serverURL,
                    login: login,
                    password: url.password
                )
                try WiredSyncDaemonIPC.waitForPairRegistration(
                    remotePath: directory.path,
                    serverURL: serverURL,
                    login: login
                )
                let syncResult = try WiredSyncDaemonIPC.syncNow(
                    remotePath: directory.path,
                    serverURL: serverURL,
                    login: login
                )
                await MainActor.run {
                    pairedSyncRemotePaths.insert(normalizeSyncRemotePath(directory.path))
                    setSyncPairLocalOverride(.sticky(active: true, until: Date().addingTimeInterval(15)), for: directory.path)
                    // Delay the reconciliation refresh so the daemon has time to settle;
                    // the manual insert above is already the correct optimistic state.
                    scheduleSyncPairStatusRefresh(delayNanoseconds: 2_000_000_000, force: true, showProgress: false)
                    debugLogSyncStatuses(
                        context: "activate.success remote=\(normalizeSyncRemotePath(directory.path)) matched=\(syncResult.matched) launched=\(syncResult.launched)"
                    )
                    syncActivationNotice = SyncActivationNotice(
                        title: "Sync Enabled",
                        message: "Pair created for:\n\(directory.path)\n↔\n\(localURL.path)\nMode: \(mode)\n\nSync matched: \(syncResult.matched), launched: \(syncResult.launched)"
                    )
                }
            } catch {
                await MainActor.run {
                    setSyncPairLocalOverride(nil, for: directory.path)
                    debugLogSyncStatuses(context: "activate.error remote=\(normalizeSyncRemotePath(directory.path)) error=\(error.localizedDescription)")
                    syncActivationNotice = SyncActivationNotice(
                        title: "Sync Error",
                        message: error.localizedDescription
                    )
                }
            }
        }
#endif
    }

    private func setLabel(_ label: FileLabelValue, on items: [FileItem]) {
        Task {
            for item in items {
                do {
                    try await filesViewModel.setFileLabel(path: item.path, label: label)
                } catch {
                    filesViewModel.error = error
                }
            }
        }
    }

    private func syncNow(for directory: FileItem) {
#if os(macOS)
        let serverURL = currentSyncServerURL
        let login = currentSyncLogin
        Task.detached(priority: .userInitiated) {
            do {
                let result = try WiredSyncDaemonIPC.syncNow(
                    remotePath: directory.path,
                    serverURL: serverURL,
                    login: login
                )
                await MainActor.run {
                    refreshSyncPairStatus(force: true, showProgress: false)
                    debugLogSyncStatuses(
                        context: "sync_now.success remote=\(normalizeSyncRemotePath(directory.path)) matched=\(result.matched) launched=\(result.launched)"
                    )
                    syncActivationNotice = SyncActivationNotice(
                        title: result.launched > 0 ? "Sync Triggered" : "Sync Already Running",
                        message: result.launched > 0
                            ? "Immediate sync requested for:\n\(directory.path)"
                            : "A sync cycle is already running for:\n\(directory.path)\n\nWait for completion and check wiredsyncd logs."
                    )
                }
            } catch {
                await MainActor.run {
                    debugLogSyncStatuses(context: "sync_now.error remote=\(normalizeSyncRemotePath(directory.path)) error=\(error.localizedDescription)")
                    syncActivationNotice = SyncActivationNotice(
                        title: "Sync Error",
                        message: error.localizedDescription
                    )
                }
            }
        }
#endif
    }

    private func deactivateSync(for directory: FileItem) {
#if os(macOS)
        guard let connection = runtime.connection as? AsyncConnection,
              let url = connection.url else {
            syncActivationNotice = SyncActivationNotice(
                title: "Sync Error",
                message: "No active Wired connection available for sync deactivation."
            )
            return
        }

        let serverURL = "\(url.hostname):\(url.port)"
        let login = url.login.trimmingCharacters(in: .whitespacesAndNewlines)
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                setSyncPairLocalOverride(.checking(active: false), for: directory.path)
            }
            do {
                try WiredSyncDaemonIPC.removePairForRemote(remotePath: directory.path, serverURL: serverURL, login: login)
                await MainActor.run {
                    pairedSyncRemotePaths.remove(normalizeSyncRemotePath(directory.path))
                    setSyncPairLocalOverride(.sticky(active: false, until: Date().addingTimeInterval(15)), for: directory.path)
                    debugLogSyncStatuses(context: "deactivate.success remote=\(normalizeSyncRemotePath(directory.path))")
                    syncActivationNotice = SyncActivationNotice(
                        title: "Sync Disabled",
                        message: "Pair removed for:\n\(directory.path)"
                    )
                    // Delay the reconciliation refresh so the daemon has time to settle;
                    // the manual remove above is already the correct optimistic state.
                    scheduleSyncPairStatusRefresh(delayNanoseconds: 2_000_000_000, force: true, showProgress: false)
                }
            } catch {
                await MainActor.run {
                    setSyncPairLocalOverride(nil, for: directory.path)
                    debugLogSyncStatuses(context: "deactivate.error remote=\(normalizeSyncRemotePath(directory.path)) error=\(error.localizedDescription)")
                    syncActivationNotice = SyncActivationNotice(
                        title: "Sync Error",
                        message: error.localizedDescription
                    )
                }
            }
        }
#endif
    }

    private func requestDeactivateSync(for directory: FileItem) {
        pendingDeactivateSyncDirectory = directory
        showDeactivateSyncConfirmation = true
    }

    private func refreshSyncPairStatus(force: Bool = false, showProgress: Bool = true) {
#if os(macOS)
        let now = Date()
        if !force, now.timeIntervalSince(lastSyncPairStatusRefreshAt) < 1.0 {
            return
        }
        lastSyncPairStatusRefreshAt = now

        let token = UUID()
        syncPairStatusRefreshToken = token
        if showProgress {
            isSyncPairStatusRefreshing = true
        }
        let serverURL = currentSyncServerURL
        let login = currentSyncLogin

        Task.detached(priority: .utility) {
            do {
                // Prefer the live daemon view, but reconcile it with the persisted daemon
                // state on disk. This keeps the UI truthful during daemon restarts and
                // socket hiccups instead of flashing false "inactive" statuses.
                let liveDescriptors = try WiredSyncDaemonIPC.listPairedDescriptors(serverURL: serverURL, login: login)
                let livePaths = Set(liveDescriptors.filter { !$0.paused }.map(\.remotePath))
                let persistedPaths = WiredSyncDaemonIPC.persistedPairedRemotePaths(serverURL: serverURL, login: login)
                let paths = livePaths.union(persistedPaths)
                await MainActor.run {
                    guard syncPairStatusRefreshToken == token else { return }
                    var effectivePaths = paths
                    var nextOverrides = syncPairLocalOverrides
                    for (path, override) in syncPairLocalOverrides {
                        switch override {
                        case .checking(let active):
                            if active {
                                effectivePaths.insert(path)
                            } else {
                                effectivePaths.remove(path)
                            }
                        case .sticky(let active, let until):
                            let daemonAgrees = active ? paths.contains(path) : !paths.contains(path)
                            if daemonAgrees || until <= Date() {
                                nextOverrides.removeValue(forKey: path)
                            } else if active {
                                effectivePaths.insert(path)
                            } else {
                                effectivePaths.remove(path)
                            }
                        }
                    }
                    syncPairLocalOverrides = nextOverrides
                    pairedSyncDescriptors = liveDescriptors
                    pairedSyncRemotePaths = effectivePaths
                    bumpSyncPairStatusVersion()
                    isSyncPairStatusRefreshing = false
                    debugLogSyncStatuses(context: "refresh.success", livePaths: livePaths, persistedPaths: persistedPaths)
                    reconcileSyncPairModesIfNeeded(descriptors: liveDescriptors)
                }
            } catch {
                let persistedPaths = WiredSyncDaemonIPC.persistedPairedRemotePaths(serverURL: serverURL, login: login)
                await MainActor.run {
                    guard syncPairStatusRefreshToken == token else { return }
                    if !persistedPaths.isEmpty {
                        var effectivePaths = persistedPaths
                        var nextOverrides = syncPairLocalOverrides
                        for (path, override) in syncPairLocalOverrides {
                            switch override {
                            case .checking(let active):
                                if active {
                                    effectivePaths.insert(path)
                                } else {
                                    effectivePaths.remove(path)
                                }
                            case .sticky(let active, let until):
                                if until <= Date() {
                                    nextOverrides.removeValue(forKey: path)
                                } else if active {
                                    effectivePaths.insert(path)
                                } else {
                                    effectivePaths.remove(path)
                                }
                            }
                        }
                        syncPairLocalOverrides = nextOverrides
                        pairedSyncRemotePaths = effectivePaths
                        bumpSyncPairStatusVersion()
                    }
                    pairedSyncDescriptors = []
                    isSyncPairStatusRefreshing = false
                    debugLogSyncStatuses(context: "refresh.error \(error.localizedDescription)", persistedPaths: persistedPaths)
                }
            }
        }
#endif
    }

    private func scheduleSyncPairStatusRefresh(delayNanoseconds: UInt64 = 300_000_000, force: Bool = false, showProgress: Bool = false) {
#if os(macOS)
        syncPairStatusRefreshTask?.cancel()
        syncPairStatusRefreshTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            refreshSyncPairStatus(force: force, showProgress: showProgress)
        }
#endif
    }

    private func startSyncPairPolling() {
#if os(macOS)
        syncPairPollingTask?.cancel()
        syncPairPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                refreshSyncPairStatus(force: true, showProgress: false)
            }
        }
#endif
    }

    @ViewBuilder
    private var treeContent: some View {
        FilesTreeView(
            connectionID: connectionID,
            filesViewModel: filesViewModel,
            sortColumn: $treeSortColumn,
            sortAscending: $treeSortAscending,
            onRequestCreateFolder: { directory in
                guard canCreateFolder(in: directory) else { return }
                createFolderTargetOverride = directory
                filesViewModel.showCreateFolderSheet = true
            },
            onPrimarySelectionChange: { path in
                updatePrimarySelectionPath(path)
                registerNavigation(fromPrimarySelectionPath: path)
            },
            onSelectionItemsChange: { items in
                selectedItemsForToolbar = items
            },
            onOpenDirectory: { directory in
                Task { @MainActor in
                    guard await filesViewModel.setTreeRoot(directory.path) else { return }
                    updatePrimarySelectionPath(directory.path)
                    registerNavigation(toDirectoryPath: directory.path)
                }
            },
            onRequestUploadInDirectory: { directory in
                guard canUpload(to: directory) else { return }
                createFolderTargetOverride = directory
                filesViewModel.showFilesBrowser = true
            },
            onRequestDeleteSelection: { items in
                requestDelete(items)
            },
            onRequestDownloadSelection: { items in
                download(items)
            },
            onRequestGetInfo: { item in
                presentInfo(for: item)
            },
            onRequestSyncNow: { item in
                syncNow(for: item)
            },
            onRequestActivateSync: { item in
                activateSync(for: item)
            },
            onRequestDeactivateSync: { item in
                requestDeactivateSync(for: item)
            },
            syncPairStatusForItem: { item in
                syncPairStatus(for: item)
            },
            syncPairExistsForItem: { item in
                syncPairExists(for: item)
            },
            syncPairStatusVersion: syncPairStatusVersion,
            canSetFileType: canSetFileType,
            canGetInfoForItem: { item in
                canGetInfo(for: item)
            },
            canDownloadForItem: { item in
                canDownload(item: item)
            },
            canDeleteForItem: { item in
                canDelete(item: item)
            },
            canUploadToDirectory: { directory in
                canUpload(to: directory)
            },
            canCreateFolderInDirectory: { directory in
                canCreateFolder(in: directory)
            },
            canDropRemoteItem: { sourcePath, destinationDirectory, link in
                canDropRemoteItem(from: sourcePath, to: destinationDirectory, link: link)
            },
            canSetLabel: runtime.hasPrivilege("wired.account.file.set_label"),
            onRequestSetLabel: { items, label in
                setLabel(label, on: items)
            },
            onUploadURLs: { urls, target in
                upload(urls: urls, to: target)
            },
            onMoveRemoteItem: { sourcePath, destinationDirectory, link in
                try await moveRemoteItem(from: sourcePath, to: destinationDirectory, link: link)
            }
        )
        .environment(connectionController)
        .environment(runtime)
        .environmentObject(transfers)
        .onAppear {
            scheduleSyncPairStatusRefresh(delayNanoseconds: 0, force: true, showProgress: false)
        }
    }

    @ViewBuilder
    private var columnsContent: some View {
        FilesColumnsView(
            connectionID: connectionID,
            selectedItem: selectedItem,
            filesViewModel: filesViewModel,
            onRequestCreateFolder: { directory in
                guard canCreateFolder(in: directory) else { return }
                createFolderTargetOverride = directory
                filesViewModel.showCreateFolderSheet = true
            },
            onPrimarySelectionChange: { path in
                updatePrimarySelectionPath(path)
                registerNavigation(fromPrimarySelectionPath: path)
            },
            onSelectionItemsChange: { items in
                selectedItemsForToolbar = items
            },
            onRequestUploadInDirectory: { directory in
                guard canUpload(to: directory) else { return }
                createFolderTargetOverride = directory
                filesViewModel.showFilesBrowser = true
            },
            onRequestDeleteSelection: { items in
                requestDelete(items)
            },
            onRequestDownloadSelection: { items in
                download(items)
            },
            onRequestGetInfo: { item in
                presentInfo(for: item)
            },
            onRequestSyncNow: { item in
                syncNow(for: item)
            },
            onRequestActivateSync: { item in
                activateSync(for: item)
            },
            onRequestDeactivateSync: { item in
                requestDeactivateSync(for: item)
            },
            syncPairStatusForItem: { item in
                syncPairStatus(for: item)
            },
            syncPairExistsForItem: { item in
                syncPairExists(for: item)
            },
            syncPairStatusVersion: syncPairStatusVersion,
            canSetFileType: canSetFileType,
            canGetInfoForItem: { item in
                canGetInfo(for: item)
            },
            canDownloadForItem: { item in
                canDownload(item: item)
            },
            canDeleteForItem: { item in
                canDelete(item: item)
            },
            canUploadToDirectory: { directory in
                canUpload(to: directory)
            },
            canCreateFolderInDirectory: { directory in
                canCreateFolder(in: directory)
            },
            canDropRemoteItem: { sourcePath, destinationDirectory, link in
                canDropRemoteItem(from: sourcePath, to: destinationDirectory, link: link)
            },
            canSetLabel: runtime.hasPrivilege("wired.account.file.set_label"),
            onRequestSetLabel: { items, label in
                setLabel(label, on: items)
            },
            onUploadURLs: { urls, target in
                upload(urls: urls, to: target)
            },
            onMoveRemoteItem: { sourcePath, destinationDirectory, link in
                try await moveRemoteItem(from: sourcePath, to: destinationDirectory, link: link)
            }
        )
        .environment(connectionController)
        .environment(runtime)
        .environmentObject(transfers)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if filesViewModel.isSearchMode {
                HStack(spacing: 6) {
                    if filesViewModel.isSearching {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Searching…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let count = filesViewModel.columns.first?.items.count ?? 0
                        Text("\(count) result\(count == 1 ? "" : "s") for \u{201C}\(filesViewModel.searchText)\u{201D}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)

                Divider()
            }

            switch filesViewModel.selectedFileViewType {
            case .tree:
                treeContent

            case .columns:
                columnsContent
            }
            
            Divider()
            
            HStack {
                FilesBreadcrumb(
                    currentPath: breadcrumbPath,
                    itemForPath: itemForPath(_:),
                    onNavigate: { path in
                        Task { @MainActor in
                            await navigateToBreadcrumbPath(path)
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                
                FilesServerInfos()
            }
            .frame(height: 40)
        }
        .searchable(text: $filesViewModel.searchText)
        .wiredSearchFieldFocus()
        .onAppear {
            let persistedViewType = preferredFileViewType
            if filesViewModel.selectedFileViewType != persistedViewType {
                filesViewModel.selectedFileViewType = persistedViewType
            }
        }
        .onChange(of: filesViewModel.searchText, debounceTime: .milliseconds(500)) {
            if filesViewModel.searchText.isEmpty && filesViewModel.isSearchMode {
                currentSearchTask?.cancel()
                currentSearchTask = nil
                Task { await filesViewModel.clearSearch() }
            } else if filesViewModel.searchText.count > 2 {
                currentSearchTask?.cancel()
                currentSearchTask = nil

                triggerSearch()
            } else {
                currentSearchTask?.cancel()
                currentSearchTask = nil
                Task { await filesViewModel.clearSearch() }
            }
        }
        .fileImporter(
            isPresented: $filesViewModel.showFilesBrowser,
            allowedContentTypes: [.data, .directory],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                if let target = selectedDirectoryForUpload {
                    upload(urls: urls, to: target)
                }
            case .failure(let error):
                filesViewModel.error = error
            }
        }
        .sheet(isPresented: $filesViewModel.showCreateFolderSheet) {
            if let selectedFile = selectedDirectoryForUpload {
                FileFormView(
                    filesViewModel: filesViewModel,
                    parentDirectory: selectedFile,
                    onCreated: { createdPath in
                        guard filesViewModel.selectedFileViewType == .columns else { return }
                        Task { @MainActor in
                            let didReveal = await filesViewModel.revealRemotePath(createdPath)
                            guard didReveal else { return }
                            updatePrimarySelectionPath(createdPath)
                            registerNavigation(fromPrimarySelectionPath: createdPath)
                        }
                    }
                )
                    .environment(connectionController)
                    .environment(runtime)
            }
        }
        .onChange(of: filesViewModel.showCreateFolderSheet) { _, isPresented in
            if !isPresented {
                createFolderTargetOverride = nil
            }
        }
        .sheet(item: $infoSheetItem) { item in
            FileInfoSheet(filesViewModel: filesViewModel, file: item)
                .environment(runtime)
        }
        .alert("Delete File", isPresented: $filesViewModel.showDeleteConfirmation, actions: {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let item = selectedItem {
                    Task {
                        await filesViewModel.deleteFile(item.path)
                    }
                }
            }
        }, message: {
            Text("Are you sure you want to delete this file? This operation is not recoverable.")
        })
        .alert(
            pendingDeleteItems.count > 1 ? "Delete Files" : "Delete File",
            isPresented: $showDeleteSelectionConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {
                    pendingDeleteItems.removeAll()
                }
                Button("Delete", role: .destructive) {
                    let items = pendingDeleteItems
                    pendingDeleteItems.removeAll()

                    Task {
                        for item in items where item.path != "/" {
                            await filesViewModel.deleteFile(item.path)
                        }
                    }
                }
            },
            message: {
                Text("Are you sure you want to delete this selection? This operation is not recoverable.")
            }
        )
        .alert(item: $activeUploadConflict) { conflict in
            Alert(
                title: Text("Upload Blocked"),
                message: Text("A remote file already exists:\n\(conflict.remotePath)\n\nLocal file:\n\(conflict.localPath)"),
                dismissButton: .default(Text("OK")) {
                    processPendingUploadConflicts()
                }
            )
        }
        .alert(
            "Deactivate Sync Pair",
            isPresented: $showDeactivateSyncConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {
                    pendingDeactivateSyncDirectory = nil
                }
                Button("Deactivate", role: .destructive) {
                    if let directory = pendingDeactivateSyncDirectory {
                        deactivateSync(for: directory)
                    }
                    pendingDeactivateSyncDirectory = nil
                }
            },
            message: {
                let targetPath = pendingDeactivateSyncDirectory?.path ?? "this folder"
                Text("Disable synchronization for \(targetPath)? The local folder is kept, only the pairing is removed.")
            }
        )
        .alert(item: $syncActivationNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .errorAlert(
            error: $filesViewModel.error,
            source: "Files",
            serverName: nil,
            connectionID: connectionID
        )
        .onChange(of: filesViewModel.selectedFileViewType) { _, newValue in
            preferredFileViewType = newValue
            updatePrimarySelectionPath(nil)
            selectedSyncStatusPath = nil
            selectedItemsForToolbar.removeAll()
            Task {
                if newValue == .tree && !filesViewModel.isSearchMode {
                    await filesViewModel.loadTreeRoot()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealRemoteTransferPath)) { notification in
            guard let request = notification.object as? RemoteTransferPathRequest else { return }
            guard request.connectionID == connectionID else { return }

            Task { @MainActor in
                let didReveal = await filesViewModel.revealRemotePath(request.path)
                if didReveal {
                    registerNavigation(fromPrimarySelectionPath: request.path)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiredFileDirectoryChanged)) { notification in
            guard let event = notification.object as? RemoteDirectoryEvent else { return }
            guard event.connectionID == connectionID else { return }

            Task { @MainActor in
                filesViewModel.remoteDirectoryChanged(event.path)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiredFileDirectoryDeleted)) { notification in
            guard let event = notification.object as? RemoteDirectoryEvent else { return }
            guard event.connectionID == connectionID else { return }

            Task { @MainActor in
                await filesViewModel.remoteDirectoryDeleted(event.path)
            }
        }
        .onAppear {
            scheduleSyncPairStatusRefresh(delayNanoseconds: 0, force: true, showProgress: false)
            startSyncPairPolling()
        }
        .onChange(of: selectedSyncStatusPath) { _, _ in
            scheduleSyncPairStatusRefresh(delayNanoseconds: 300_000_000, force: false, showProgress: false)
        }
        .onDisappear {
            syncPairStatusRefreshTask?.cancel()
            syncPairPollingTask?.cancel()
            Task { @MainActor in
                await filesViewModel.clearDirectorySubscriptions()
            }
        }
    }

}
