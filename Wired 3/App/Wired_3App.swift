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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let transferManager else {
            return .terminateNow
        }

        guard transferManager.hasActiveTransfers() else {
            transferManager.prepareForTermination()
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Active transfers are in progress."
        alert.informativeText = "Quitting now will stop active transfers."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            transferManager.prepareForTermination()
            return .terminateNow
        }

        return .terminateCancel
    }
}
#endif


@main
struct Wired_3App: App {
    @State private var socketClient = SocketClient()
    @State private var controller: ConnectionController
    @State private var transfers: TransferManager
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
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bookmark.self,
            Transfer.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
#if os(macOS)
        Window("Wired 3", id: "main") {
            AppRootView(appTerminationDelegate: appTerminationDelegate)
                .environment(controller)
                .environmentObject(transfers)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Connection") {
                    controller.presentNewConnection()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
#else
        WindowGroup {
            AppRootView()
                .environment(controller)
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
    @EnvironmentObject private var transfers: TransferManager
#if os(macOS)
    let appTerminationDelegate: AppTerminationDelegate
#endif

    var body: some View {
        MainView()
#if os(macOS)
            .background(MainWindowFramePersistenceView(frameKey: "Wired3MainWindowFrame"))
#endif
            .onAppear {
                // Attach SwiftData once, and restore persisted transfers.
                transfers.attach(modelContext: modelContext)

#if os(macOS)
                appTerminationDelegate.transferManager = transfers
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
        private weak var observedWindow: NSWindow?
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
