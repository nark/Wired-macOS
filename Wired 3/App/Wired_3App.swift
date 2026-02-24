//
//  Wired_3App.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
import WiredSwift
import UserNotifications
#if os(macOS)
import AppKit
#endif

let specURL = Bundle.main.url(forResource: "wired", withExtension: "xml")!
let spec = P7Spec(withUrl: specURL)
let iconData = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")!.dataRepresentation

let byteCountFormatter = ByteCountFormatter()

#if os(macOS)
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    weak var transferManager: TransferManager?
    weak var connectionController: ConnectionController?

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let transferManager else {
            return .terminateNow
        }

        let checkConnectionsBeforeClose = UserDefaults.standard.object(forKey: "CheckActiveConnectionsBeforeClosingWindowTab") as? Bool ?? true
        let activeConnectionIDs = checkConnectionsBeforeClose ? (connectionController?.activeConnectedConnectionIDs() ?? []) : []
        let hasActiveTransfers = transferManager.hasActiveTransfers()

        guard !activeConnectionIDs.isEmpty || hasActiveTransfers else {
            transferManager.prepareForTermination()
            return .terminateNow
        }

        let alert = NSAlert()
        if !activeConnectionIDs.isEmpty && hasActiveTransfers {
            alert.messageText = "Active connections and transfers"
            alert.informativeText = "There are \(activeConnectionIDs.count) active connections and active transfers. Quitting now will stop transfers."
            alert.addButton(withTitle: "Disconnect and Quit")
            alert.addButton(withTitle: "Cancel")
        } else if !activeConnectionIDs.isEmpty {
            alert.messageText = activeConnectionIDs.count == 1 ? "Active connection" : "Active connections"
            alert.informativeText = activeConnectionIDs.count == 1
                ? "Do you want to disconnect the active connection before quitting?"
                : "Do you want to disconnect \(activeConnectionIDs.count) active connections before quitting?"
            alert.addButton(withTitle: "Disconnect and Quit")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.messageText = "Active transfers are in progress."
            alert.informativeText = "Quitting now will stop active transfers."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
        }
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if !activeConnectionIDs.isEmpty {
                connectionController?.disconnectAll()
            }
            transferManager.prepareForTermination()
            return .terminateNow
        case .alertSecondButtonReturn:
            return .terminateCancel
        default:
            return .terminateCancel
        }
    }
}

private struct MainAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let controller: ConnectionController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection") {
                controller.presentedNewConnectionWindowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
                controller.presentNewConnection()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Divider()

            Menu("New Window for Bookmark") {
                let bookmarkItems = controller.bookmarkMenuItems()
                if bookmarkItems.isEmpty {
                    Text("No Bookmarks")
                } else {
                    ForEach(bookmarkItems) { item in
                        Button(item.name) {
                            controller.requestedSelectionID = item.id
                            openWindow(id: "main")
                            controller.connectBookmark(withID: item.id)
                        }
                    }
                }
            }
            .disabled(controller.bookmarkMenuItems().isEmpty)

            Menu("New Tab for Bookmark") {
                let bookmarkItems = controller.bookmarkMenuItems()
                if bookmarkItems.isEmpty {
                    Text("No Bookmarks")
                } else {
                    ForEach(bookmarkItems) { item in
                        Button(item.name) {
                            controller.requestedSelectionID = item.id
                            openMainTab()
                            controller.connectBookmark(withID: item.id)
                        }
                    }
                }
            }
            .disabled(controller.bookmarkMenuItems().isEmpty)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Error Log") {
                openWindow(id: "error-log")
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }
    }

    private func openMainTab() {
        let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first
        let existingWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
        openWindow(id: "main")
        attachNewMainWindowAsTab(existingWindows: existingWindows, preferredSourceWindow: sourceWindow)
    }

    private func attachNewMainWindowAsTab(
        existingWindows: Set<ObjectIdentifier>,
        preferredSourceWindow: NSWindow?,
        attempt: Int = 0
    ) {
        if attempt > 10 { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let newWindow = NSApp.windows.first(where: { !existingWindows.contains(ObjectIdentifier($0)) }) else {
                attachNewMainWindowAsTab(existingWindows: existingWindows, preferredSourceWindow: preferredSourceWindow, attempt: attempt + 1)
                return
            }

            let sourceWindow = preferredSourceWindow
                ?? NSApp.windows.first(where: { existingWindows.contains(ObjectIdentifier($0)) })
                ?? NSApp.keyWindow
                ?? NSApp.mainWindow
            guard let sourceWindow, newWindow !== sourceWindow else {
                attachNewMainWindowAsTab(existingWindows: existingWindows, preferredSourceWindow: preferredSourceWindow, attempt: attempt + 1)
                return
            }

            sourceWindow.tabbingMode = .preferred
            sourceWindow.tabbingIdentifier = "WiredMain"
            newWindow.tabbingMode = .preferred
            newWindow.tabbingIdentifier = "WiredMain"
            newWindow.orderOut(nil)
            sourceWindow.addTabbedWindow(newWindow, ordered: .above)
            sourceWindow.tabGroup?.selectedWindow = newWindow
            sourceWindow.tabbingMode = .disallowed
            newWindow.tabbingMode = .disallowed
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}
#endif

@MainActor
@Observable
final class ErrorLogStore {
    private var modelContext: ModelContext?
    private let defaults = UserDefaults.standard
    private let retentionKey = "ErrorLogRetentionDays"

    func attach(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        pruneExpiredEntries()
    }

    func record(
        error: Error,
        source: String,
        serverName: String?,
        connectionID: UUID?
    ) {
        guard let modelContext else { return }

        let entry = presentableError(from: error)
        let row = ErrorLogEntry(
            source: source,
            serverName: serverName ?? "Unknown server",
            connectionID: connectionID,
            title: entry.title,
            message: entry.message,
            details: entry.details
        )

        modelContext.insert(row)
        try? modelContext.save()
        pruneExpiredEntries()
    }

    func clearAll() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ErrorLogEntry>()
        if let entries = try? modelContext.fetch(descriptor) {
            for entry in entries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }
    }

    private func retentionDays() -> Int {
        let raw = defaults.integer(forKey: retentionKey)
        return raw > 0 ? raw : 30
    }

    private func pruneExpiredEntries() {
        guard let modelContext else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays(), to: .now) ?? .distantPast
        let predicate = #Predicate<ErrorLogEntry> { $0.createdAt < cutoff }
        let descriptor = FetchDescriptor<ErrorLogEntry>(predicate: predicate)

        if let entries = try? modelContext.fetch(descriptor), !entries.isEmpty {
            for entry in entries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }
    }
}

#if os(macOS)
private struct ErrorLogWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorLogStore.self) private var errorLogStore
    @Query(sort: \ErrorLogEntry.createdAt, order: .reverse) private var entries: [ErrorLogEntry]
    @State private var filterText: String = ""

    private var filteredEntries: [ErrorLogEntry] {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return entries }

        return entries.filter { entry in
            entry.title.lowercased().contains(needle)
                || entry.message.lowercased().contains(needle)
                || entry.serverName.lowercased().contains(needle)
                || entry.source.lowercased().contains(needle)
                || entry.details.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Filter errors", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                Button("Clear") {
                    errorLogStore.clearAll()
                }
                .disabled(entries.isEmpty)
            }
            .padding(12)

            List(filteredEntries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.serverName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.title)
                        .font(.headline)
                    Text(entry.message)
                        .font(.subheadline)
                    Text("[\(entry.source)] \(entry.details)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Errors",
                        systemImage: "checkmark.circle",
                        description: Text("No logged errors for the current filter.")
                    )
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .onAppear {
            errorLogStore.attach(modelContext: modelContext)
        }
    }
}
#endif


@main
struct Wired_3App: App {
    @State private var socketClient = SocketClient()
    @State private var controller: ConnectionController
    @State private var transfers: TransferManager
    @State private var errorLogStore = ErrorLogStore()
    @State private var errorToastCenter = ErrorToastCenter()
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) private var appTerminationDelegate
#endif
    
    init() {
        let socket = SocketClient()
        let cc = ConnectionController(socketClient: socket)
        let tm = TransferManager(spec: spec!, connectionController: cc)
        
        self._controller = State(initialValue: cc)
        self._transfers = State(initialValue: tm)
        
        byteCountFormatter.allowedUnits = [.useAll]
        byteCountFormatter.countStyle = .file
        byteCountFormatter.zeroPadsFractionDigits = true
#if os(macOS)
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
        NSWindow.allowsAutomaticWindowTabbing = false
        Self.clearSavedWindowState()
#endif
    }

#if os(macOS)
    private static func clearSavedWindowState() {
        let bundleID = Bundle.main.bundleIdentifier ?? "fr.read-write.Wired-3"
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Saved Application State/\(bundleID).savedState")
        try? FileManager.default.removeItem(atPath: path)
    }
#endif
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bookmark.self,
            ErrorLogEntry.self,
            Transfer.self,
            StoredPrivateConversation.self,
            StoredPrivateMessage.self,
            StoredBroadcastConversation.self,
            StoredBroadcastMessage.self,
            StoredMessageSelection.self,
        ])
        let storeURL = Self.swiftDataStoreURL()
        Self.migrateLegacySandboxStoreIfNeeded(to: storeURL)
        print("SwiftData store URL: \(storeURL.path)")
        let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private static func swiftDataStoreURL() -> URL {
        let fm = FileManager.default
        let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolderName = Bundle.main.bundleIdentifier ?? "fr.read-write.Wired-3"

#if os(macOS)
        let appFolderURL = appSupportURL.appendingPathComponent(appFolderName, isDirectory: true)
        try? fm.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        return appFolderURL.appendingPathComponent("default.store")
#else
        let appFolderURL = appSupportURL.appendingPathComponent(appFolderName, isDirectory: true)
        try? fm.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        return appFolderURL.appendingPathComponent("default.store")
#endif
    }

    private static func migrateLegacySandboxStoreIfNeeded(to destinationStoreURL: URL) {
#if os(macOS)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destinationStoreURL.path) else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "fr.read-write.Wired-3"
        let legacyBaseURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support", isDirectory: true)

        let oldFlatStoreURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("default.store")

        let candidateStores = [
            legacyBaseURL.appendingPathComponent("default.store"),
            oldFlatStoreURL,
        ]

        guard let sourceStoreURL = candidateStores.first(where: { source in
            source.path != destinationStoreURL.path && fm.fileExists(atPath: source.path)
        }) else {
            return
        }

        for suffix in ["", "-shm", "-wal"] {
            let sourceURL = URL(fileURLWithPath: sourceStoreURL.path + suffix)
            let destinationURL = URL(fileURLWithPath: destinationStoreURL.path + suffix)
            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            try? fm.copyItem(at: sourceURL, to: destinationURL)
        }
#endif
    }

    var body: some Scene {
#if os(macOS)
        WindowGroup("Wired 3", id: "main") {
            AppRootView(appTerminationDelegate: appTerminationDelegate)
                .environment(controller)
                .environment(errorLogStore)
                .environment(errorToastCenter)
                .environmentObject(transfers)
        }
#if os(macOS)
        .restorationBehavior(.disabled)
#endif
        .modelContainer(sharedModelContainer)
        .commands {
            MainAppCommands(controller: controller)
        }

        Window("Error Log", id: "error-log") {
            ErrorLogWindowView()
                .environment(errorLogStore)
                .environment(errorToastCenter)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }
#else
        WindowGroup {
            AppRootView()
                .environment(controller)
                .environment(errorLogStore)
                .environment(errorToastCenter)
                .environmentObject(transfers)
        }
        .modelContainer(sharedModelContainer)
#endif
    }
}

/// A small root view that has access to SwiftData's ModelContext.
/// This avoids threading ModelContext manually through your whole view tree.
private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ErrorLogStore.self) private var errorLogStore
    @Environment(ErrorToastCenter.self) private var errorToastCenter
    @EnvironmentObject private var transfers: TransferManager
#if os(macOS)
    let appTerminationDelegate: AppTerminationDelegate
#endif

    var body: some View {
        MainView()
            .overlay(alignment: .bottomTrailing) {
                ErrorToastOverlay()
                    .environment(errorToastCenter)
            }
#if os(macOS)
            .background(MainWindowFramePersistenceView(frameKey: "Wired3MainWindowFrame"))
#endif
            .onAppear {
                // Attach SwiftData once, and restore persisted transfers.
                transfers.attach(modelContext: modelContext)
                connectionController.attach(modelContext: modelContext)
                errorLogStore.attach(modelContext: modelContext)

#if os(macOS)
                appTerminationDelegate.transferManager = transfers
                appTerminationDelegate.connectionController = connectionController
#endif

                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.badge, .alert, .sound]
                ) { granted, _ in
                    print("Notifications permission:", granted)
                }
            }
            .onOpenURL { url in
                guard let action = connectionController.handleIncomingURL(url) else { return }
                guard let remotePath = action.remotePath else { return }
                Task {
                    await startRemoteDownload(for: action.connectionID, remotePath: remotePath)
                }
            }
    }

    private func startRemoteDownload(for connectionID: UUID, remotePath: String) async {
        guard remotePath.hasPrefix("/") else {
            if let runtime = connectionController.runtime(for: connectionID) {
                runtime.lastError = WiredError(
                    withTitle: "Download Error",
                    message: "Invalid remote path: \(remotePath)"
                )
            }
            return
        }

        guard let connection = await waitForConnectionReady(connectionID: connectionID, timeoutSeconds: 20) else {
            if let runtime = connectionController.runtime(for: connectionID) {
                runtime.lastError = WiredError(
                    withTitle: "Download Error",
                    message: "Unable to connect to server before starting download for \(remotePath)."
                )
            }
            return
        }

        _ = connection
        // Deep-link behavior: server is authoritative, so queue a direct file download.
        let file = FileItem((remotePath as NSString).lastPathComponent, path: remotePath, type: .file)
        if let runtime = connectionController.runtime(for: connectionID) {
            runtime.selectedTab = .files
        }
        handleQueuedDownload(file: file, connectionID: connectionID, remotePath: remotePath)
    }

    private func handleQueuedDownload(file: FileItem, connectionID: UUID, remotePath: String) {
        switch transfers.queueDownload(file, with: connectionID, overwriteExistingFile: false) {
        case .started, .resumed:
            break
        case .needsOverwrite(let destination):
            if let runtime = connectionController.runtime(for: connectionID) {
                runtime.lastError = WiredError(
                    withTitle: "Download Blocked",
                    message: "A local file already exists at \(destination)."
                )
            }
        case .failed:
            if let runtime = connectionController.runtime(for: connectionID) {
                runtime.lastError = WiredError(
                    withTitle: "Download Error",
                    message: "Unable to start download for \(remotePath)."
                )
            }
        }
    }

    private func waitForConnectionReady(connectionID: UUID, timeoutSeconds: TimeInterval) async -> AsyncConnection? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if let connection = connectionController.runtime(for: connectionID)?.connection as? AsyncConnection {
                return connection
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        return nil
    }
}

#if os(macOS)
private struct MainWindowFramePersistenceView: NSViewRepresentable {
    let frameKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator(frameKey: frameKey)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        private let frameKey: String
        private var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var restoredWindowNumber: Int?

        init(frameKey: String) {
            self.frameKey = frameKey
        }

        deinit {
            removeObservers()
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                guard self.observedWindow !== window else { return }
                self.observe(window: window)
            }
        }

        private func observe(window: NSWindow) {
            removeObservers()
            observedWindow = window
            restoreFrameIfNeeded(for: window)

            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.willCloseNotification
            ]

            observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.saveFrame()
                }
            }
        }

        private func restoreFrameIfNeeded(for window: NSWindow) {
            guard restoredWindowNumber != window.windowNumber else { return }
            restoredWindowNumber = window.windowNumber

            guard let frameString = UserDefaults.standard.string(forKey: frameKey) else { return }
            let frame = NSRectFromString(frameString)
            guard frame.width > 0, frame.height > 0 else { return }
            window.setFrame(frame, display: true)
        }

        private func saveFrame() {
            guard let window = observedWindow else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers.removeAll()
        }
    }
}
#endif
