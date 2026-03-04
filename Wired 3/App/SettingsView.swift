//
//  SettingsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import DebouncedOnChange
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    private enum SettingsPane: Hashable {
        case general
        case chat
        case files
        case events

#if os(macOS)
        var contentSize: NSSize {
            switch self {
            case .general: return NSSize(width: 560, height: 380)
            case .chat: return NSSize(width: 460, height: 240)
            case .files: return NSSize(width: 460, height: 220)
            case .events: return NSSize(width: 940, height: 620)
            }
        }
#endif
    }

#if os(macOS)
    @State private var settingsWindow: NSWindow?
    @State private var hasAppliedInitialSize = false
#endif
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        TabView(selection: $selectedPane) {
            Tab("General", systemImage: "gear", value: .general) {
                GeneralSettingsView()
            }
            
            Tab("Chat", systemImage: "message.fill", value: .chat) {
                ChatSettingsView()
            }
            
            Tab("Files", systemImage: "folder.fill", value: .files) {
                FilesSettingsView()
            }

            Tab("Events", systemImage: "bell.fill", value: .events) {
                EventsSettingsView()
            }
        }
#if os(macOS)
        .background(
            SettingsWindowAccessor { window in
                guard let window else { return }
                if settingsWindow !== window {
                    settingsWindow = window
                    hasAppliedInitialSize = false
                }
                if !hasAppliedInitialSize {
                    resizeWindow(for: selectedPane, animated: false)
                    hasAppliedInitialSize = true
                }
            }
        )
        .onAppear {
            if !hasAppliedInitialSize {
                resizeWindow(for: selectedPane, animated: false)
                hasAppliedInitialSize = true
            }
        }
        .onChange(of: selectedPane) { _, pane in
            resizeWindow(for: pane, animated: false)
        }
        .scenePadding()
        .frame(minWidth: 460, minHeight: 220)
#endif
    }

#if os(macOS)
    private func resizeWindow(for pane: SettingsPane, animated: Bool) {
        guard let window = settingsWindow else { return }

        let targetContentRect = NSRect(origin: .zero, size: pane.contentSize)
        let targetFrame = window.frameRect(forContentRect: targetContentRect)
        let currentFrame = window.frame

        guard abs(currentFrame.width - targetFrame.width) > 0.5 ||
                abs(currentFrame.height - targetFrame.height) > 0.5 else {
            return
        }

        let newOrigin = NSPoint(
            x: currentFrame.midX - (targetFrame.width / 2.0),
            y: currentFrame.maxY - targetFrame.height
        )
        let adjustedFrame = NSRect(origin: newOrigin, size: targetFrame.size)
        window.setFrame(adjustedFrame, display: true, animate: animated)
    }
#endif
}

#if os(macOS)
private struct SettingsWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}
#endif


extension Notification.Name {
    static let wiredUserNickDidChange       = Notification.Name("wiredUserNickDidChange")
    static let wiredUserStatusDidChange     = Notification.Name("wiredUserStatusDidChange")
    static let wiredUserIconDidChange       = Notification.Name("wiredUserIconDidChange")
}

struct GeneralSettingsView: View {
    @AppStorage("UserNick") var userNick: String = "Wired Swift"
    @AppStorage("UserStatus") var userStatus = ""
    @AppStorage("UserIcon") var userIcon: String?
    @AppStorage("CheckActiveConnectionsBeforeClosingWindowTab")
    var checkActiveConnectionsBeforeClosingWindowTab: Bool = true

    @State private var debouncer = Debouncer()
    @State private var showIconImporter = false

    private func notifyUserStatusChange() {
        NotificationCenter.default.post(name: .wiredUserStatusDidChange, object: userStatus)
    }
    
    var userIconImage: Image {
        if let base64 = userIcon,
           let image = AppImageCodec.image(fromBase64: base64) {
            return image
        }

        return Image("DefaultIcon")
    }
    
    var body: some View {
        Form {
#if os(macOS)
            LabeledContent("Icon") {
                userIconImage.resizable()
                    .frame(width: 32, height: 32)
                
                Spacer()
                
                Button("Select Icon") {
                    showIconImporter.toggle()
                }
                .fileImporter(
                            isPresented: $showIconImporter,
                            allowedContentTypes: [.image],
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                            case .success(let urls):
                                if let url = urls.first {
                                    self.handleImage(url)
                                }
                            case .failure(let error):
                                print("Import error:", error)
                            }
                        }
                .controlSize(.small)
            }
            
            Divider()
#elseif os(iOS)
            LabeledContent("Icon") {
                userIconImage.resizable()
                    .frame(width: 32, height: 32)
            }
#endif
            
#if os(macOS)
            LabeledContent("Nickname") {
                TextField("Nickname", text: $userNick)
                    .labelsHidden()
                    .onChange(of: userNick, debounceTime: .milliseconds(800), debouncer: $debouncer) {
                        NotificationCenter.default.post(name: .wiredUserNickDidChange, object: userNick)
                    }
                    .onKeyPress(.return) {
                        debouncer.cancel()
                        NotificationCenter.default.post(name: .wiredUserNickDidChange, object: userNick)
                        return .handled
                    }
            }
#else
            HStack {
                Text("Nickname")
                Spacer()
                TextField("Nickname", text: $userNick)
                    .multilineTextAlignment(.trailing)
                    .bold()
            }
#endif
            
#if os(macOS)
            LabeledContent("Status") {
                TextField("Status", text: $userStatus)
                    .labelsHidden()
                    .onChange(of: userStatus, debounceTime: .milliseconds(800), debouncer: $debouncer) {
                        notifyUserStatusChange()
                    }
                    .onKeyPress(.return) {
                        debouncer.cancel()
                        notifyUserStatusChange()
                        return .handled
                    }
            }

            LabeledContent("Window Closing") {
                Toggle("Check for active connections before closing window/tab",
                       isOn: $checkActiveConnectionsBeforeClosingWindowTab)
                .toggleStyle(.checkbox)
            }
#else
            HStack {
                Text("Status")
                Spacer()
                TextField("Status", text: $userStatus)
                    .multilineTextAlignment(.trailing)
                    .bold()
            }
#endif
        }
        .onDisappear {
            // Ensure an empty status is propagated even if the debounce has not fired yet.
            debouncer.cancel()
            notifyUserStatusChange()
        }
        .onChange(of: userIcon) { oldValue, newValue in
            NotificationCenter.default.post(name: .wiredUserIconDidChange, object: userIcon)
        }
    }
    
#if os(macOS)
    func handleImage(_ url: URL) {
        Task.detached {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let image = NSImage(data: data)
            
            let resized = image?.resized(to: CGSize(width: 32, height: 32))

            await MainActor.run {
                if let resized {
                    userIcon = AppImageCodec.base64(from: resized)
                }
            }
        }
    }
#endif
}


@propertyWrapper
struct AppStorageCodable<T: Codable>: DynamicProperty {
    @AppStorage private var data: Data
    private let defaultValue: T

    init(key: String, defaultValue: T) {
        self._data = AppStorage(wrappedValue: Data(), key)
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get {
            guard let value = try? JSONDecoder().decode(T.self, from: data) else {
                return defaultValue
            }
            return value
        }
        nonmutating set {
            data = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

struct ChatSettingsView: View {
    @AppStorage("SubstituteEmoji") var substituteEmoji: Bool = true
    
    @AppStorageCodable(key: "EmojiSubstitutions", defaultValue: [
        ":-)": "😊",
        ":)":  "😊",
        ";-)": "😉",
        ";)":  "😉",
        ":-D": "😀",
        ":D":  "😀",
        "<3":  "❤️",
        "+1":  "👍"
    ])
    var emojiSubstitutions: [String: String]

    
    var body: some View {
        LabeledContent("Substitute Emoji") {
            Toggle("", isOn: $substituteEmoji)
        }
    }
}

struct FilesSettingsView: View {
    @AppStorage("DownloadPath") var downloadPath: String = NSHomeDirectory().stringByAppendingPathComponent(path: "Downloads")
    
    var body: some View {
        Text(downloadPath)
    }
}

struct EventsSettingsView: View {
    private struct EventTableRow: Identifiable {
        enum Kind {
            case section(String)
            case event(WiredEventTag)
        }

        let id: String
        let kind: Kind

        var tag: WiredEventTag? {
            if case .event(let tag) = kind { return tag }
            return nil
        }

        static func event(_ tag: WiredEventTag) -> EventTableRow {
            EventTableRow(id: "event-\(tag.rawValue)", kind: .event(tag))
        }

        static func section(_ title: String) -> EventTableRow {
            EventTableRow(id: "section-\(title)", kind: .section(title))
        }
    }

    @AppStorage(WiredEventsStore.volumeKey) private var eventsVolume: Double = 1.0
    @AppStorageCodable(
        key: WiredEventsStore.configurationsKey,
        defaultValue: WiredEventsStore.defaultConfigurations()
    )
    private var configurations: [WiredEventConfiguration]

    var body: some View {
        Group {
#if os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("Volume", systemImage: "speaker.wave.2.fill")
                        .labelStyle(.titleAndIcon)
                        .frame(width: 90, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { eventsVolume },
                            set: { eventsVolume = $0 }
                        ),
                        in: 0.0 ... 1.0
                    )
                    .frame(width: 220)

                    Text("\(Int((eventsVolume * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Table(tableRows) {
                    TableColumn("Event") { row in
                        if let tag = row.tag {
                            HStack(spacing: 8) {
                                Image(systemName: eventSymbol(for: tag))
                                    .frame(width: 14, alignment: .center)
                                    .foregroundStyle(.secondary)
                                Text(tag.title)
                            }
                            .padding(.leading, 14)
                        } else {
                            if case .section(let title) = row.kind {
                                Text(title.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 220, ideal: 240, max: .infinity)

                    TableColumn("Sound") { row in
                        if let tag = row.tag {
                            HStack(spacing: 6) {
                                Toggle("", isOn: boolBinding(for: tag, \.playSound))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .onChange(of: configuration(for: tag).playSound) { _, enabled in
                                        if enabled {
                                            playPreviewSound(for: tag)
                                        }
                                    }

                                Picker("", selection: soundBinding(for: tag)) {
                                    ForEach(WiredEventsStore.availableSounds, id: \.self) { sound in
                                        Text(sound).tag(sound)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .disabled(!configuration(for: tag).playSound)
                            }
                        } else {
                            EmptyView()
                        }
                    }
                    .width(140)

                    TableColumn("Bounce in Dock") { row in
                        if let tag = row.tag {
                            Toggle("", isOn: boolBinding(for: tag, \.bounceInDock))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                        } else {
                            EmptyView()
                        }
                    }
                    .width(90)

                    TableColumn("Post in Chat") { row in
                        if let tag = row.tag {
                            if supportsPostInChat(tag: tag) {
                                Toggle("", isOn: boolBinding(for: tag, \.postInChat))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                            } else {
                                Image(systemName: "minus")
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            EmptyView()
                        }
                    }
                    .width(78)

                    TableColumn("Alert") { row in
                        if let tag = row.tag {
                            if supportsShowAlert(tag: tag) {
                                // TODO: Hook this toggle to a real in-app alert path once legacy WCEventsShowDialog behavior is restored.
                                Toggle("", isOn: boolBinding(for: tag, \.showAlert))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                            } else {
                                Image(systemName: "minus")
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            EmptyView()
                        }
                    }
                    .width(56)

                    TableColumn("Notification") { row in
                        if let tag = row.tag {
                            Toggle("", isOn: boolBinding(for: tag, \.notificationCenter))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                        } else {
                            EmptyView()
                        }
                    }
                    .width(84)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
#else
            Form {
                Text("Events settings table is available on macOS.")
            }
#endif
        }
        .onAppear {
            eventsVolume = Double(WiredEventsStore.loadVolume())
            configurations = normalized(configurations)
        }
        .onChange(of: eventsVolume) { _, value in
            WiredEventsStore.saveVolume(Float(value))
        }
        .onChange(of: configurations) { _, value in
            WiredEventsStore.saveConfigurations(normalized(value))
        }
    }

    private var tableRows: [EventTableRow] {
        let connection: [WiredEventTag] = [.serverConnected, .serverDisconnected, .error]
        let activity: [WiredEventTag] = [
            .userJoined, .userChangedNick, .userChangedStatus, .userLeft,
            .chatReceived, .chatSent, .highlightedChatReceived, .chatInvitationReceived,
            .messageReceived, .broadcastReceived, .boardPostAdded
        ]
        let transfers: [WiredEventTag] = [.transferStarted, .transferFinished]

        return (
            [.section("Connection")] +
            connection.map { .event($0) } +
            [.section("Activity")] +
            activity.map { .event($0) } +
            [.section("Transfers")] +
            transfers.map { .event($0) }
        )
    }

    private func supportsPostInChat(tag: WiredEventTag) -> Bool {
        switch tag {
        case .userJoined, .userChangedNick, .userChangedStatus, .userLeft:
            return true
        default:
            return false
        }
    }

    private func supportsShowAlert(tag: WiredEventTag) -> Bool {
        switch tag {
        case .messageReceived, .broadcastReceived:
            return true
        default:
            return false
        }
    }

    private func configuration(for tag: WiredEventTag) -> WiredEventConfiguration {
        normalized(configurations).first(where: { $0.tag == tag }) ?? WiredEventConfiguration(tag: tag)
    }

    private func boolBinding(for tag: WiredEventTag, _ keyPath: WritableKeyPath<WiredEventConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { configuration(for: tag)[keyPath: keyPath] },
            set: { newValue in
                var all = normalized(configurations)
                if let index = all.firstIndex(where: { $0.tag == tag }) {
                    all[index][keyPath: keyPath] = newValue
                } else {
                    var config = WiredEventConfiguration(tag: tag)
                    config[keyPath: keyPath] = newValue
                    all.append(config)
                }
                configurations = normalized(all)
            }
        )
    }

    private func soundBinding(for tag: WiredEventTag) -> Binding<String> {
        Binding(
            get: { configuration(for: tag).sound ?? WiredEventsStore.defaultSoundName },
            set: { newValue in
                var all = normalized(configurations)
                if let index = all.firstIndex(where: { $0.tag == tag }) {
                    all[index].sound = newValue
                } else {
                    var config = WiredEventConfiguration(tag: tag)
                    config.sound = newValue
                    all.append(config)
                }
                configurations = normalized(all)
                if configuration(for: tag).playSound {
                    playPreviewSound(for: tag)
                }
            }
        )
    }

    private func normalized(_ values: [WiredEventConfiguration]) -> [WiredEventConfiguration] {
        var byTag = Dictionary(uniqueKeysWithValues: WiredEventsStore.defaultConfigurations().map { ($0.tag, $0) })
        for config in values {
            byTag[config.tag] = config
        }

        return WiredEventTag.menuOrder.compactMap { tag in
            guard var config = byTag[tag] else { return nil }
            if config.sound == nil || config.sound?.isEmpty == true {
                config.sound = WiredEventsStore.defaultSoundName
            }
            return config
        }
    }

    private func eventSymbol(for tag: WiredEventTag) -> String {
        switch tag {
        case .serverConnected: return "link.badge.plus"
        case .serverDisconnected: return "xmark.circle"
        case .error: return "exclamationmark.triangle"
        case .userJoined: return "person.badge.plus"
        case .userChangedNick: return "character.cursor.ibeam"
        case .userChangedStatus: return "person.text.rectangle"
        case .userLeft: return "person.badge.minus"
        case .chatReceived: return "message"
        case .chatSent: return "paperplane"
        case .highlightedChatReceived: return "text.bubble"
        case .chatInvitationReceived: return "person.2.badge.plus"
        case .messageReceived: return "envelope.badge"
        case .broadcastReceived: return "megaphone"
        case .boardPostAdded: return "text.page.badge.magnifyingglass"
        case .transferStarted: return "arrow.down.circle"
        case .transferFinished: return "checkmark.circle"
        }
    }

    private func playPreviewSound(for tag: WiredEventTag) {
#if os(macOS)
        let soundName = configuration(for: tag).sound ?? WiredEventsStore.defaultSoundName
        guard let sound = NSSound(named: NSSound.Name(soundName)) else { return }
        sound.volume = Float(max(0.0, min(eventsVolume, 1.0)))
        sound.play()
#endif
    }
}
