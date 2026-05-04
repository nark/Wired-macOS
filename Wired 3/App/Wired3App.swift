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
import CoreText
#endif

let spec = WiredProtocolSpec.bundledSpec()!
let iconData = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")!.dataRepresentation

let byteCountFormatter = ByteCountFormatter()

#if os(macOS)
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    weak var transferManager: TransferManager?
    weak var connectionController: ConnectionController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let fileMenu = NSApp.mainMenu?.item(withTitle: "File") {
            fileMenu.title = "Connection"
        }
    }

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
    @FocusedBinding(\.wiredSearchFieldFocused) private var isSearchFieldFocused: Bool?

    let controller: ConnectionController

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(OverlayGlyphs.aboutLabel) {
                let optionPressed = NSApp.currentEvent?.modifierFlags.contains(.option) == true

                if optionPressed {
                    OverlayInfoWindow.shared.present()
                } else {
                    NSApp.orderFrontStandardAboutPanel(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(before: .windowSize) {
            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .chats
                }
            } label: {
                Label {
                    Text("Chats")
                } icon: {
                    Image(systemName: "text.bubble")
                }
            }
            .keyboardShortcut("c", modifiers: [.option])
            .disabled(controller.activeConnectionID == nil)

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .messages
                }
            } label: {
                Label {
                    Text("Messages")
                } icon: {
                    Image(systemName: "ellipsis.message")
                }
            }
            .keyboardShortcut("m", modifiers: [.option])
            .disabled(controller.activeConnectionID == nil)

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .boards
                }
            } label: {
                Label {
                    Text("Boards")
                } icon: {
                    Image(systemName: "newspaper")
                }
            }
            .keyboardShortcut("b", modifiers: [.option])
            .disabled(controller.activeConnectionID == nil)

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .files
                }
            } label: {
                Label {
                    Text("Files")
                } icon: {
                    Image(systemName: "folder")
                }
            }
            .keyboardShortcut("f", modifiers: [.option])
            .disabled(controller.activeConnectionID == nil)

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .settings
                }
            } label: {
                Label {
                    Text("Settings")
                } icon: {
                    Image(systemName: "gear")
                }
            }
            .keyboardShortcut("s", modifiers: [.option])
            .disabled(controller.activeConnectionID == nil)

            Divider()
        }


        CommandMenu("Find") {
            Button("Find") {
                isSearchFieldFocused = true
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(isSearchFieldFocused == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button {
                controller.presentedNewConnectionWindowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
                controller.presentNewConnection()
            } label: {
                Label {
                    Text("New Connection")
                } icon: {
                    Image(systemName: "network")
                }
            }
            .keyboardShortcut("k", modifiers: [.command])

            Divider()

            Menu {
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
            } label: {
                Label {
                    Text("Window Tab for Bookmark")
                } icon: {
                    Image(systemName: "macwindow.badge.plus")
                }
            }
            .disabled(controller.bookmarkMenuItems().isEmpty)

            Menu {
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
            } label: {
                Label {
                    Text("New Tab for Bookmark")
                } icon: {
                    Image(systemName: "macwindow.on.rectangle")
                }
            }
            .disabled(controller.bookmarkMenuItems().isEmpty)

            Divider()

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    controller.disconnect(connectionID: id, runtime: runtime)
                }
            } label: {
                Label {
                    Text("Disconnect")
                } icon: {
                    Image(systemName: "cable.connector.slash")
                }
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!controller.canDisconnect)

            Button {
                controller.reconnectActiveConnection()
            } label: {
                Label {
                    Text("Reconnect")
                } icon: {
                    Image(systemName: "cable.connector.horizontal")
                }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!controller.canReconnect)

            Divider()

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .infos
                }
            } label: {
                Label {
                    Text("Show Server Info")
                } icon: {
                    Image(systemName: "info.circle.fill")
                }
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(!controller.canShowServerInfo)

            Divider()

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .chats
                    runtime.pendingTopicSheet = true
                }
            } label: {
                Label {
                    Text("Set Topic")
                } icon: {
                    Image(systemName: "message.badge.waveform.fill")
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!controller.canSetTopic)

            Button {
                if let id = controller.activeConnectionID, let runtime = controller.runtime(for: id) {
                    runtime.selectedTab = .messages
                    runtime.pendingBroadcastConversation = true
                }
            } label: {
                Label {
                    Text("New Broadcast")
                } icon: {
                    Image(systemName: "megaphone.fill")
                }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!controller.canBroadcast)

            Divider()

            Button {
                controller.presentChangePasswordWindowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
                if let id = controller.activeConnectionID {
                    controller.presentChangePassword = id
                }
            } label: {
                Label {
                    Text("Change password...")
                } icon: {
                    Image(systemName: "lock.fill")
                }
            }
            .disabled(!controller.canChangePassword)

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
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}

private enum OverlayGlyphs {
    static var aboutLabel: String {
        let appName =
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            "App"
        return "About \(appName)"
    }

    static var leftLine: String { decode([163, 140, 143, 147, 133, 192, 148, 136, 133, 192, 151, 143, 146, 140, 132, 204], key: 0xE0) }
    static var rightLine: String { decode([159, 128, 149, 158, 208, 132, 152, 149, 208, 158, 181, 136, 132], key: 0xF0) }
    static var lowerLine: String { decode([147, 181, 174, 165, 178, 179, 162, 231, 179, 168, 231, 138, 168, 181, 181, 174, 180], key: 0xC7) }

    private static func decode(_ bytes: [UInt8], key: UInt8) -> String {
        String(bytes: bytes.map { $0 ^ key }, encoding: .utf8) ?? ""
    }
}

private final class OverlayInfoWindow: NSWindow, NSWindowDelegate {
    static let shared = OverlayInfoWindow()

    private init() {
        let frame = Self.bannerFrame()

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let view = OverlayInfoView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]

        delegate = self
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        let frame = Self.bannerFrame()
        setFrame(frame, display: false)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override var canBecomeKey: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        close()
    }

    override func mouseDown(with event: NSEvent) {
        close()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    @objc private func applicationDidResignActive() {
        close()
    }

    private static func bannerFrame() -> NSRect {
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: 1320, height: 120)
        }

        let width = mainScreen.frame.width
        let height = max(90.0, width / 11.0)
        return NSRect(
            x: mainScreen.frame.minX,
            y: mainScreen.frame.midY - (height / 2.0),
            width: width,
            height: height
        )
    }
}

private final class OverlayInfoView: NSView {
    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startAnimation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        startAnimation()
    }

    deinit {
        animationTimer?.invalidate()
    }

    override var isOpaque: Bool {
        false
    }

    private func startAnimation() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationPhase += 0.045
            self.needsDisplay = true
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let width = bounds.width
        let baseFontSize = max(26.0, width / 13.8)
        let fontSize = min(baseFontSize, max(22.0, bounds.height * 0.48))

        let centeredParagraphStyle = NSMutableParagraphStyle()
        centeredParagraphStyle.alignment = .center

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]

        let primaryLeft = NSAttributedString(string: OverlayGlyphs.leftLine, attributes: baseAttributes)
        let primaryRight = NSMutableAttributedString(string: OverlayGlyphs.rightLine, attributes: baseAttributes)
        let secondaryFont = NSFont.systemFont(ofSize: max(12.0, fontSize * 0.24), weight: .semibold)
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: secondaryFont,
            .paragraphStyle: centeredParagraphStyle
        ]
        let secondaryLine = NSAttributedString(string: OverlayGlyphs.lowerLine, attributes: secondaryAttributes)

        let emphasisRange = (primaryRight.string as NSString).range(of: "E")
        if emphasisRange.location != NSNotFound {
            primaryRight.addAttribute(
                .foregroundColor,
                value: NSColor.red.shadow(withLevel: 0.5) ?? NSColor.red,
                range: emphasisRange
            )
        }

        let mainTextHeight = ceil(max(primaryLeft.size().height, primaryRight.size().height))
        let secondaryHeight = max(14.0, ceil(secondaryLine.size().height))
        let gap = max(8.0, fontSize * 0.20)
        let topPadding = max(4.0, bounds.height * 0.03)
        let mainAreaHeight = max(0.0, bounds.height - secondaryHeight - gap - topPadding)
        let mainY = secondaryHeight + gap + max(0.0, (mainAreaHeight - mainTextHeight) * 0.5)
        let mainRect = NSRect(x: 0, y: mainY, width: bounds.width, height: mainTextHeight)

        let centerGap = max(18.0, fontSize * 0.45)
        let leftSize = primaryLeft.size()
        let rightSize = primaryRight.size()
        let textY = mainRect.minY + (mainRect.height - max(leftSize.height, rightSize.height)) * 0.5

        let leftOrigin = NSPoint(
            x: max(8.0, bounds.midX - (centerGap * 0.5) - leftSize.width),
            y: textY
        )
        primaryLeft.draw(at: leftOrigin)

        let rightOriginX = min(bounds.width - rightSize.width - 8.0, bounds.midX + (centerGap * 0.5))
        context.saveGState()
        context.translateBy(x: rightOriginX + rightSize.width, y: 0)
        context.scaleBy(x: -1, y: 1)
        primaryRight.draw(at: NSPoint(x: 0, y: textY))
        context.restoreGState()

        let secondarySize = secondaryLine.size()
        let secondaryRect = NSRect(
            x: (bounds.width - secondarySize.width) * 0.5,
            y: max(4.0, bounds.height * 0.03),
            width: secondarySize.width,
            height: secondaryHeight
        )

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: secondaryRect.minX, y: secondaryRect.minY + (secondaryRect.height - secondarySize.height) * 0.5)
        context.setTextDrawingMode(.clip)

        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(
            string: OverlayGlyphs.lowerLine,
            attributes: [.font: secondaryFont]
        ))
        CTLineDraw(ctLine, context)

        let palette: [NSColor] = [
            NSColor.systemPink.withAlphaComponent(0.36),
            NSColor.systemOrange.withAlphaComponent(0.34),
            NSColor.systemYellow.withAlphaComponent(0.30),
            NSColor.systemGreen.withAlphaComponent(0.34),
            NSColor.systemTeal.withAlphaComponent(0.36),
            NSColor.systemBlue.withAlphaComponent(0.34),
            NSColor.systemIndigo.withAlphaComponent(0.34),
            NSColor.systemPurple.withAlphaComponent(0.36)
        ]

        let bandWidth = max(18.0, secondaryRect.width / 5.5)
        for index in 0..<10 {
            let phase = animationPhase + CGFloat(index) * 0.62
            let x = secondaryRect.minX - bandWidth + CGFloat(index) * (bandWidth * 0.82) + sin(phase) * (bandWidth * 0.35)
            let rect = NSRect(
                x: x,
                y: secondaryRect.minY - 6.0,
                width: bandWidth,
                height: secondaryRect.height + 12.0
            )
            context.setFillColor(palette[index % palette.count].cgColor)
            context.fill(rect)
        }

        let glowX = secondaryRect.midX + cos(animationPhase * 1.6) * (secondaryRect.width * 0.23)
        let glowY = secondaryRect.midY + sin(animationPhase * 2.1) * 2.0
        let glowRect = NSRect(x: glowX - 34.0, y: glowY - 18.0, width: 68.0, height: 36.0)
        context.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.fillEllipse(in: glowRect)

        context.restoreGState()

        let secondaryStrokeAttributes: [NSAttributedString.Key: Any] = [
            .font: secondaryFont,
            .foregroundColor: NSColor.black.withAlphaComponent(0.20),
            .strokeColor: NSColor.black.withAlphaComponent(0.48),
            .strokeWidth: 1.2,
            .paragraphStyle: centeredParagraphStyle
        ]
        NSAttributedString(string: OverlayGlyphs.lowerLine, attributes: secondaryStrokeAttributes).draw(in: secondaryRect)
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

@MainActor
final class DefaultTrackerBookmarkSeeder {
    private var modelContext: ModelContext?
    private let defaults: UserDefaults
    private let seedKey = "DidSeedDefaultTrackerBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func attach(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        seedIfNeeded()
    }

    private func seedIfNeeded() {
        guard let modelContext else { return }
        guard !defaults.bool(forKey: seedKey) else { return }

        let existingBookmarks = (try? modelContext.fetch(FetchDescriptor<TrackerBookmark>())) ?? []
        guard existingBookmarks.isEmpty else {
            defaults.set(true, forKey: seedKey)
            return
        }

        let bookmark = TrackerBookmark(
            name: "Wired Tracker",
            hostname: "wired.read-write.fr",
            port: 4871,
            login: "guest",
            sortOrder: 0
        )
        modelContext.insert(bookmark)

        do {
            try modelContext.save()
            defaults.set(true, forKey: seedKey)
        } catch {
            modelContext.delete(bookmark)
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
struct Wired3App: App {
    @State private var socketClient = SocketClient()
    @State private var controller: ConnectionController
    @State private var trackerBrowser = TrackerBrowserController()
    @State private var defaultTrackerSeeder = DefaultTrackerBookmarkSeeder()
    @State private var transfers: TransferManager
    @State private var errorLogStore = ErrorLogStore()
    @State private var errorToastCenter = ErrorToastCenter()
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) private var appTerminationDelegate
#endif

    init() {
        let socket = SocketClient()
        let cc = ConnectionController(socketClient: socket)
        let tm = TransferManager(spec: spec, connectionController: cc)

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
        WiredSyncDaemonIPC.ensureDaemonIsCurrentVersion()
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
            TrackerBookmark.self,
            ErrorLogEntry.self,
            Transfer.self,
            StoredPrivateConversation.self,
            StoredPrivateMessage.self,
            StoredBroadcastConversation.self,
            StoredBroadcastMessage.self,
            StoredMessageSelection.self,
            StoredChatMessage.self
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
            oldFlatStoreURL
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
        WindowGroup(appDisplayName, id: "main") {
            AppRootView(defaultTrackerSeeder: defaultTrackerSeeder, appTerminationDelegate: appTerminationDelegate)
                .environment(controller)
                .environment(trackerBrowser)
                .environment(errorLogStore)
                .environment(errorToastCenter)
                .environmentObject(transfers)
        }
        .wiredDisableRestorationBehaviorIfAvailable()
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

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 980, height: 640)
        .windowResizability(.contentSize)

        Window("Chat History", id: "chat-history") {
            ChatHistoryWindow()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1000, height: 700)
#else
        WindowGroup {
            AppRootView(defaultTrackerSeeder: defaultTrackerSeeder)
                .environment(controller)
                .environment(trackerBrowser)
                .environment(errorLogStore)
                .environment(errorToastCenter)
                .environmentObject(transfers)
        }
        .modelContainer(sharedModelContainer)
#endif
    }
}

private var appDisplayName: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
    "Wired"
}

#if os(macOS)
private extension Scene {
    func wiredDisableRestorationBehaviorIfAvailable() -> some Scene {
        if #available(macOS 15.0, *) {
            return self.restorationBehavior(.disabled)
        }

        return self
    }
}
#endif

/// A small root view that has access to SwiftData's ModelContext.
/// This avoids threading ModelContext manually through your whole view tree.
private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionController.self) private var connectionController
    @Environment(TrackerBrowserController.self) private var trackerBrowser
    @Environment(ErrorLogStore.self) private var errorLogStore
    @Environment(ErrorToastCenter.self) private var errorToastCenter
    @EnvironmentObject private var transfers: TransferManager
    let defaultTrackerSeeder: DefaultTrackerBookmarkSeeder
#if os(macOS)
    let appTerminationDelegate: AppTerminationDelegate
#endif

    var body: some View {
        MainView()
            .environment(trackerBrowser)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
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
                defaultTrackerSeeder.attach(modelContext: modelContext)
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
