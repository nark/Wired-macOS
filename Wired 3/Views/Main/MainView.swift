    //
//  ContentView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var bookmarks: [Bookmark]
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager

    @State private var windowConnectionID: UUID? = nil
    @State private var listSelectionID: UUID? = nil
    @State private var editedBookmark: Bookmark? = nil
    
    @State private var showDeleteBookmarkConfirmation: Bool = false
    @State private var bookmarkToDelete: Bookmark? = nil

    @AppStorage("transfersHeight") private var transfersHeight: Double = 0
    @AppStorage("CheckActiveConnectionsBeforeClosingWindowTab")
    private var checkActiveConnectionsBeforeClosingWindowTab: Bool = true
    @State private var lastTransfersHeight: CGFloat = 200
    @State private var isTransfersVisible = false
    @State private var isTabBarVisible = false

    private var activeTransfersCount: Int {
        transfers.transfers.filter { !$0.isStopped() }.count
    }

    private var windowBookmark: Bookmark? {
        guard let id = windowConnectionID else { return nil }
        return bookmarks.first(where: { $0.id == id })
    }

    private var windowTemporaryConnection: TemporaryConnection? {
        guard let id = windowConnectionID else { return nil }
        return connectionController.temporaryConnection(for: id)
    }

    private var windowConnectionName: String? {
        windowBookmark?.name ?? windowTemporaryConnection?.name
    }

    private var windowRuntime: ConnectionRuntime? {
        guard let id = windowConnectionID else { return nil }
        return connectionController.runtime(for: id)
    }

    private var tabTitle: String {
        let baseTitle = windowConnectionName ?? "Wired 3"

        guard let runtime = windowRuntime else { return baseTitle }
        let hasConnectionIssue =
            runtime.status == .disconnected &&
            (runtime.lastError != nil || runtime.isAutoReconnectScheduled)

        return hasConnectionIssue ? "⚠︎ \(baseTitle)" : baseTitle
    }

    private var newConnectionSheetBinding: Binding<NewConnectionDraft?> {
        Binding(
            get: {
                guard !connectionController.suppressPresentedNewConnectionSheet else { return nil }
                return connectionController.presentedNewConnection
            },
            set: { newValue in
                connectionController.presentedNewConnection = newValue
            }
        )
    }

    private var listSelectionBinding: Binding<UUID?> {
        Binding(
            get: { listSelectionID },
            set: { newValue in
                listSelectionID = newValue
                guard let newValue else { return }

#if os(macOS)
                guard connectionController.hasWindowAssociation(for: newValue) else { return }
                if connectionController.focusWindow(for: newValue) {
                    // Keep local selection tied to this window's connection.
                    listSelectionID = windowConnectionID
                    return
                }
                // Do not replace current detail when we cannot focus an existing tab/window.
                return
#endif
            }
        )
    }

    var body: some View {
        @Bindable var connectionController = connectionController

        VSplitView {
            mainContent

            transfersPanel
                .frame(
                    minHeight: isTransfersVisible ? 200 : 0,
                    maxHeight: isTransfersVisible ? .infinity : 0
                )
                .animation(.smooth, value: isTransfersVisible)
        }
#if os(macOS)
        .navigationTitle(tabTitle)
        .background(
            MainWindowCloseConfirmationView(
                selectedConnectionID: windowConnectionID,
                checkBeforeClosing: checkActiveConnectionsBeforeClosingWindowTab,
                connectionController: connectionController,
                onWindowBecameKey: {
                    listSelectionID = windowConnectionID
                },
                onTabBarVisibilityChanged: { isVisible in
                    isTabBarVisible = isVisible
                }
            )
            .frame(width: 0, height: 0)
        )
#endif
        .sheet(item: newConnectionSheetBinding) { draft in
            NewConnectionFormView(draft: draft) { id in
                if windowConnectionID == nil || windowConnectionID == id {
                    windowConnectionID = id
                    listSelectionID = id
                    connectionController.activeConnectionID = id
                } else {
                    connectionController.suppressPresentedNewConnectionSheet = true
                    connectionController.requestedSelectionID = id
                    openMainTab()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        connectionController.suppressPresentedNewConnectionSheet = false
                    }
                }
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: listSelectionBinding) {
                    Section {
                        ForEach(bookmarks, id: \.id) { bookmark in
                            ConnectionRowView(
                                connectionID: bookmark.id,
                                name: bookmark.name
                            )
                            .environment(connectionController)
                            .tag(bookmark.id)
                        }
                    } header: {
                        Text("Favorites")
                    }

                    if !connectionController.temporaryConnections.isEmpty {
                        Section {
                            ForEach(connectionController.temporaryConnections, id: \.id) { temporary in
                                ConnectionRowView(
                                    connectionID: temporary.id,
                                    name: temporary.name
                                )
                                .environment(connectionController)
                                .tag(temporary.id)
                            }
                        } header: {
                            Text("Connections")
                        }
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { selection in
                    connectionContextMenu(for: selection)
                } primaryAction: { selection in
                    handleConnectionPrimaryAction(selection)
                }

                Divider()

                HStack(spacing: 0) {
                    Button {
                        toggleTransfers()

                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: isTransfersVisible ? "menubar.arrow.down.rectangle" : "menubar.arrow.up.rectangle")

                            if activeTransfersCount > 0 {
                                Text(activeTransfersCount > 99 ? "99" : "\(activeTransfersCount)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color.red)
                                    )
                                    .offset(x: 10, y: -8)
                                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: activeTransfersCount)
                    }
                    .foregroundStyle(isTransfersVisible ? .blue : .black)
                    .buttonStyle(.plain)
                    .help("Show Transfers")

                    Spacer()
                }
                .padding(9)
            }
#if os(macOS)
            .padding(.top, isTabBarVisible ? 30 : 0)
#endif
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigation) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button {
                        connectionController.presentNewConnection()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editedBookmark) { bookmark in
                BookmarkFormView(bookmark: bookmark)
            }
            .alert("Delete Bookmark", isPresented: $showDeleteBookmarkConfirmation) {
                Button("Cancel", role: .cancel) {
                    
                }
                
                Button("Delete", role: .destructive) {
                    deleteBookmark()
                }
            }
        } detail: {
            ZStack {
                if let bookmark = windowBookmark {
                    TabsView(
                        connectionID: bookmark.id,
                        connectionName: bookmark.name,
                        bookmark: bookmark
                    )
                    .environment(connectionController)
                    .environmentObject(transfers)
                    .id(bookmark.id)
                } else if let temporary = windowTemporaryConnection {
                    TabsView(
                        connectionID: temporary.id,
                        connectionName: temporary.name,
                        bookmark: nil
                    )
                    .environment(connectionController)
                    .environmentObject(transfers)
                    .id(temporary.id)
                } else {
                    Text("Select an item")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .onAppear {
            performInitialLaunchFlowIfNeeded()
            consumePendingSelectionIfNeeded()
            restoreWindowConnectionIfNeeded()
            listSelectionID = windowConnectionID
            connectionController.activeConnectionID = windowConnectionID
        }
        .onChange(of: activeTransfersCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            guard !isTransfersVisible else { return }

            withAnimation(.smooth) {
                isTransfersVisible = true
                transfersHeight = max(lastTransfersHeight, 200)
            }
        }
        .onChange(of: connectionController.requestedSelectionID) { _, newValue in
            _ = newValue
            consumePendingSelectionIfNeeded()
            restoreWindowConnectionIfNeeded()
        }
        .onChange(of: windowConnectionID) { _, newValue in
            connectionController.activeConnectionID = newValue
        }
    }

    private var transfersPanel: some View {
        Color.gray.opacity(0.15)
            .overlay(
                TransfersView()
                    .environmentObject(transfers)
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.height) { _, newHeight in
                            guard isTransfersVisible else { return }
                            guard newHeight > 30 else { return }

                            transfersHeight = newHeight
                            lastTransfersHeight = newHeight
                        }
                }
            )
    }
    
    private func deleteBookmark() {
        if let bookmarkToDelete  {
            // disconnect if needed
            if let runtime = connectionController.runtime(for: bookmarkToDelete.id) {
                connectionController.disconnect(connectionID: bookmarkToDelete.id, runtime: runtime)
            }
            
            modelContext.delete(bookmarkToDelete)
            self.bookmarkToDelete = nil
        }
        
        showDeleteBookmarkConfirmation = false
    }
    
    private func disconnect(_ id:UUID) {
        if let runtime = connectionController.runtime(for: id) {
            connectionController.disconnect(connectionID: id, runtime: runtime)
        }
    }

    private func toggleTransfers() {
        if isTransfersVisible {
            lastTransfersHeight = transfersHeight
            transfersHeight = 0
        } else {
            transfersHeight = lastTransfersHeight
        }
        isTransfersVisible.toggle()
    }

    private func consumePendingSelectionIfNeeded() {
        guard windowConnectionID == nil,
              let requested = connectionController.requestedSelectionID else {
            return
        }
        windowConnectionID = requested
        listSelectionID = requested
        connectionController.requestedSelectionID = nil
        connectionController.activeConnectionID = requested
    }

    private func restoreWindowConnectionIfNeeded() {
        guard windowConnectionID == nil else { return }

        if let listSelectionID,
           hasConnectionContext(listSelectionID) {
            windowConnectionID = listSelectionID
            connectionController.activeConnectionID = listSelectionID
            return
        }

        if let firstActive = connectionController.firstActiveConnectionID() {
            windowConnectionID = firstActive
            listSelectionID = firstActive
            connectionController.activeConnectionID = firstActive
        }
    }

    private func performInitialLaunchFlowIfNeeded() {
        guard !connectionController.didPerformInitialLaunchFlow else { return }
        connectionController.didPerformInitialLaunchFlow = true

        let startupBookmarks = bookmarks.filter { $0.connectAtStartup }
        guard !startupBookmarks.isEmpty else {
            connectionController.presentNewConnection()
            return
        }

        if let first = startupBookmarks.first {
            windowConnectionID = first.id
            listSelectionID = first.id
            connectionController.activeConnectionID = first.id
            connectionController.connect(first)
        }

        for (index, bookmark) in startupBookmarks.dropFirst().enumerated() {
            let delay = 0.10 * Double(index + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                connectInNewTab(bookmark)
            }
        }
    }

    private func openOrSelectBookmark(_ bookmark: Bookmark) {
        // WiredClient-like behavior: opening a bookmark creates a dedicated tab/window.
        if hasConnectionContext(bookmark.id) {
#if os(macOS)
            if connectionController.focusWindow(for: bookmark.id) {
                return
            }
            // If we cannot resolve an existing tab/window for this active connection,
            // avoid replacing the current detail content.
            return
#endif
        }

        // Reuse the empty main window for the first connection.
        if windowConnectionID == nil {
            windowConnectionID = bookmark.id
            listSelectionID = bookmark.id
            connectionController.activeConnectionID = bookmark.id
            connectionController.connect(bookmark)
            return
        }

        connectInNewTab(bookmark)
    }

    private func bookmark(for id: UUID) -> Bookmark? {
        bookmarks.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func connectionContextMenu(for selection: Set<UUID>) -> some View {
        if let id = selection.first {
            if let bookmark = bookmark(for: id) {
                if connectionController.isConnected(id) {
                    Button("Disconnect") {
                        disconnect(id)
                    }
                } else {
                    Button("Connect") {
                        openOrSelectBookmark(bookmark)
                    }

                    Button("Connect in New Window") {
                        connectInNewWindow(bookmark)
                    }

                    Button("Connect in New Tab") {
                        connectInNewTab(bookmark)
                    }
                }

                Divider()

                Button("Edit") {
                    editedBookmark = bookmark
                }

                Divider()

                Button("Delete") {
                    showDeleteBookmarkConfirmation = true
                    bookmarkToDelete = bookmark
                }
            } else if connectionController.isConnected(id) {
                Button("Disconnect") {
                    disconnect(id)
                }
            }
        }
    }

    private func handleConnectionPrimaryAction(_ selection: Set<UUID>) {
        guard let id = selection.first else { return }
        if let bookmark = bookmark(for: id) {
            if connectionController.isConnected(id) {
                openOrSelectBookmark(bookmark)
            } else {
                connectInNewTab(bookmark)
            }
            return
        }

        guard hasConnectionContext(id) else { return }
        windowConnectionID = id
        listSelectionID = id
        connectionController.activeConnectionID = id
    }

    private func hasConnectionContext(_ id: UUID) -> Bool {
        connectionController.runtime(for: id) != nil || connectionController.isConnected(id)
    }

    private func openMainWindow() {
        openWindow(id: "main")
    }

    private func openMainTab() {
        let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first
        let existingWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
        openMainWindow()
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

    private func connectInNewWindow(_ bookmark: Bookmark) {
        connectionController.requestedSelectionID = bookmark.id
        openMainWindow()
        connectionController.connect(bookmark)
    }

    private func connectInNewTab(_ bookmark: Bookmark) {
        connectionController.requestedSelectionID = bookmark.id
        openMainTab()
        connectionController.connect(bookmark)
    }
}

#if os(macOS)
private struct MainWindowCloseConfirmationView: NSViewRepresentable {
    let selectedConnectionID: UUID?
    let checkBeforeClosing: Bool
    let connectionController: ConnectionController
    let onWindowBecameKey: () -> Void
    let onTabBarVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.selectedConnectionID = selectedConnectionID
        context.coordinator.checkBeforeClosing = checkBeforeClosing
        context.coordinator.connectionController = connectionController
        context.coordinator.onWindowBecameKey = onWindowBecameKey
        context.coordinator.onTabBarVisibilityChanged = onTabBarVisibilityChanged
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedConnectionID: selectedConnectionID,
            checkBeforeClosing: checkBeforeClosing,
            connectionController: connectionController,
            onWindowBecameKey: onWindowBecameKey,
            onTabBarVisibilityChanged: onTabBarVisibilityChanged
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        fileprivate var selectedConnectionID: UUID?
        fileprivate var checkBeforeClosing: Bool
        fileprivate weak var connectionController: ConnectionController?
        fileprivate var onWindowBecameKey: () -> Void
        fileprivate var onTabBarVisibilityChanged: (Bool) -> Void

        private var observedWindow: NSWindow?
        private var closeDelegate: WindowCloseDelegate?
        private var windowObservers: [NSObjectProtocol] = []
        private let newWindowForTabSelector = NSSelectorFromString("newWindowForTab:")

        init(
            selectedConnectionID: UUID?,
            checkBeforeClosing: Bool,
            connectionController: ConnectionController,
            onWindowBecameKey: @escaping () -> Void,
            onTabBarVisibilityChanged: @escaping (Bool) -> Void
        ) {
            self.selectedConnectionID = selectedConnectionID
            self.checkBeforeClosing = checkBeforeClosing
            self.connectionController = connectionController
            self.onWindowBecameKey = onWindowBecameKey
            self.onTabBarVisibilityChanged = onTabBarVisibilityChanged
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                guard self.observedWindow !== window else {
                    self.syncDelegateState()
                    self.updateTabBarVisibility(for: window)
                    return
                }
                self.observe(window: window)
            }
        }

        private func observe(window: NSWindow) {
            if let previousWindow = observedWindow,
               previousWindow !== window,
               let connectionController {
                connectionController.unregisterWindow(previousWindow)
            }

            window.tabbingMode = .disallowed
            window.tabbingIdentifier = "WiredMain"

            observedWindow = window
            if closeDelegate == nil {
                closeDelegate = WindowCloseDelegate()
            }
            closeDelegate?.install(on: window)
            installWindowObservers(for: window)
            syncDelegateState()
            updateTabBarVisibility(for: window)
            scheduleNativeNewTabButtonHiding(for: window)
        }

        private func syncDelegateState() {
            closeDelegate?.selectedConnectionID = selectedConnectionID
            closeDelegate?.checkBeforeClosing = checkBeforeClosing
            closeDelegate?.connectionController = connectionController
            if let observedWindow, let connectionController {
                connectionController.registerWindow(observedWindow, for: selectedConnectionID)
            }
        }

        private func installWindowObservers(for window: NSWindow) {
            windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
            windowObservers.removeAll()

            let keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onWindowBecameKey()
                    if let window = self?.observedWindow {
                        self?.updateTabBarVisibility(for: window)
                        self?.scheduleNativeNewTabButtonHiding(for: window)
                    }
                }
            }
            windowObservers.append(keyObserver)

            let closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let observedWindow = self.observedWindow,
                       let connectionController = self.connectionController {
                        connectionController.unregisterWindow(observedWindow)
                    }
                    self.observedWindow = nil
                }
            }
            windowObservers.append(closeObserver)
        }

        private func scheduleNativeNewTabButtonHiding(for window: NSWindow) {
            let delays: [TimeInterval] = [0.0, 0.05, 0.2]

            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.hideNativeNewTabButton(in: window)
                    self.updateTabBarVisibility(for: window)
                }
            }
        }

        private func updateTabBarVisibility(for window: NSWindow) {
            let isVisible = (window.tabGroup?.windows.count ?? 0) > 1
            onTabBarVisibilityChanged(isVisible)
        }

        private func hideNativeNewTabButton(in window: NSWindow) {
            guard let root = window.contentView?.superview else { return }
            hideNativeNewTabButton(in: root)
        }

        private func hideNativeNewTabButton(in view: NSView) {
            if let control = view as? NSControl,
               shouldHideNativeNewTabControl(control, in: view) {
                let superview = control.superview
                control.removeFromSuperview()
                superview?.needsLayout = true
                superview?.layoutSubtreeIfNeeded()
                return
            }

            for subview in view.subviews {
                hideNativeNewTabButton(in: subview)
            }
        }

        private func shouldHideNativeNewTabControl(_ control: NSControl, in view: NSView) -> Bool {
            if let action = control.action {
                let actionName = NSStringFromSelector(action).lowercased()
                if action == newWindowForTabSelector || actionName.contains("newwindowfortab") {
                    return true
                }
            }

            if let button = control as? NSButton {
                let tooltip = button.toolTip?.lowercased() ?? ""
                if tooltip.contains("new tab")
                    || tooltip.contains("create a new tab")
                    || tooltip.contains("nouvel onglet")
                    || tooltip.contains("nouveau onglet") {
                    return true
                }

                let className = String(describing: type(of: view)).lowercased()
                if className.contains("tabbar") || className.contains("tabbar") {
                    if button.title.isEmpty || button.title == "+" {
                        return true
                    }
                }
            }

            return false
        }

        deinit {
            windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
            if let observedWindow, let connectionController {
                let window = observedWindow
                let controller = connectionController
                Task { @MainActor in
                    controller.unregisterWindow(window)
                }
            }
        }
    }
}

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var connectionController: ConnectionController?
    var selectedConnectionID: UUID?
    var checkBeforeClosing: Bool = true

    private weak var originalDelegate: NSWindowDelegate?

    func install(on window: NSWindow) {
        if window.delegate !== self {
            originalDelegate = window.delegate
            window.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if originalDelegate?.windowShouldClose?(sender) == false {
            return false
        }

        guard checkBeforeClosing,
              let connectionController,
              let selectedConnectionID,
              connectionController.isConnected(selectedConnectionID),
              let runtime = connectionController.runtime(for: selectedConnectionID),
              runtime.status == .connected else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Active connection"
        alert.informativeText = "Do you want to disconnect the active connection before closing this window/tab?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disconnect and Close")
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            connectionController.disconnect(connectionID: selectedConnectionID, runtime: runtime)
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        originalDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        originalDelegate?.windowDidResignKey?(notification)
    }

    @objc
    func windowWillOrderOnScreen(_ notification: Notification) {
        // Keep empty on purpose: some AppKit paths send this selector to the window delegate
        // even though it's not exposed through NSWindowDelegate in Swift.
    }

    @objc
    func window(_ window: NSWindow, newWindowForTab sender: Any?) -> NSWindow? {
        connectionController?.presentNewConnection()
        return nil
    }
}
#endif
