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
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
        case general
        case chat
        case files
        case events

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .chat: return "Chat"
            case .files: return "Files"
            case .events: return "Events"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "gearshape"
            case .chat: return "message"
            case .files: return "folder"
            case .events: return "bell"
            }
        }
    }

    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        Group {
#if os(macOS)
            NavigationSplitView(columnVisibility: .constant(.all)) {
                List(SettingsPane.allCases, selection: $selectedPane) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .tag(pane)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
                .toolbar(removing: .sidebarToggle)
            }
            detail: {
                NavigationStack {
                    Group {
                        if selectedPane == .events {
                            detailView(for: selectedPane)
                                .padding(20)
                        } else {
                            ScrollView {
                                detailView(for: selectedPane)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(20)
                            }
                        }
                    }
                    .navigationTitle(selectedPane.title)
                }
                .id(selectedPane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                //.background(Color(nsColor: .underPageBackgroundColor))
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 980, minHeight: 640)
#else
            TabView {
                Tab("General", systemImage: "gear") {
                    GeneralSettingsView()
                }

                Tab("Chat", systemImage: "message.fill") {
                    ChatSettingsView()
                }

                Tab("Files", systemImage: "folder.fill") {
                    FilesSettingsView()
                }

                Tab("Events", systemImage: "bell.fill") {
                    EventsSettingsView()
                }
            }
#endif
        }
    }

#if os(macOS)
    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsView()
        case .chat:
            ChatSettingsView()
        case .files:
            FilesSettingsView()
        case .events:
            EventsSettingsView()
        }
    }
#endif
}


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
#if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Identity") {
                SettingsRow("Icon") {
                    HStack(spacing: 8) {
                        userIconImage.resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Button("Choose...") {
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
                }
                SettingsDivider()
                SettingsRow("Nickname") {
                    TextField("Nickname", text: $userNick)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onChange(of: userNick, debounceTime: .milliseconds(800), debouncer: $debouncer) {
                            NotificationCenter.default.post(name: .wiredUserNickDidChange, object: userNick)
                        }
                        .onKeyPress(.return) {
                            debouncer.cancel()
                            NotificationCenter.default.post(name: .wiredUserNickDidChange, object: userNick)
                            return .handled
                        }
                }
                SettingsDivider()
                SettingsRow("Status") {
                    TextField("Status", text: $userStatus)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onChange(of: userStatus, debounceTime: .milliseconds(800), debouncer: $debouncer) {
                            notifyUserStatusChange()
                        }
                        .onKeyPress(.return) {
                            debouncer.cancel()
                            notifyUserStatusChange()
                            return .handled
                        }
                }
            }

            SettingsSection(title: "Behavior") {
                SettingsRow("Window Closing") {
                    Toggle("Check for active connections before closing",
                           isOn: $checkActiveConnectionsBeforeClosingWindowTab)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
        .onDisappear {
            debouncer.cancel()
            notifyUserStatusChange()
        }
        .onChange(of: userIcon) { oldValue, newValue in
            NotificationCenter.default.post(name: .wiredUserIconDidChange, object: userIcon)
        }
#else
        Form {
            LabeledContent("Icon") {
                userIconImage.resizable()
                    .frame(width: 32, height: 32)
            }
            HStack {
                Text("Nickname")
                Spacer()
                TextField("Nickname", text: $userNick)
                    .multilineTextAlignment(.trailing)
                    .bold()
            }
            HStack {
                Text("Status")
                Spacer()
                TextField("Status", text: $userStatus)
                    .multilineTextAlignment(.trailing)
                    .bold()
            }
        }
        .onDisappear {
            debouncer.cancel()
            notifyUserStatusChange()
        }
        .onChange(of: userIcon) { oldValue, newValue in
            NotificationCenter.default.post(name: .wiredUserIconDidChange, object: userIcon)
        }
#endif
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

    var projectedValue: Binding<T> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(swiftUIColor: Color) {
#if os(macOS)
        let nativeColor = NSColor(swiftUIColor).usingColorSpace(.sRGB) ?? NSColor.white
        self.red = Double(nativeColor.redComponent)
        self.green = Double(nativeColor.greenComponent)
        self.blue = Double(nativeColor.blueComponent)
        self.alpha = Double(nativeColor.alphaComponent)
#else
        let nativeColor = UIColor(swiftUIColor)
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        nativeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.alpha = Double(alpha)
#endif
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var contrastTextColor: Color {
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance > 0.6 ? .black : .white
    }
}

struct ChatHighlightRule: Identifiable, Codable, Equatable {
    var id: UUID
    var keyword: String
    var color: CodableColor

    init(id: UUID = UUID(), keyword: String, color: CodableColor) {
        self.id = id
        self.keyword = keyword
        self.color = color
    }

    static var defaultRule: ChatHighlightRule {
        ChatHighlightRule(
            keyword: "",
            color: CodableColor(red: 0.98, green: 0.89, blue: 0.18)
        )
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

    @AppStorageCodable(key: "ChatHighlightRules", defaultValue: [])
    var highlightRules: [ChatHighlightRule]

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Messages") {
                SettingsRow("Substitute Emoji") {
                    Toggle("", isOn: $substituteEmoji)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsSection(title: "Highlights") {
                SettingsNavigationRow("Hightlights") {
                    HStack(spacing: 8) {
                        if !highlightRules.isEmpty {
                            Text("\(highlightRules.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } destination: {
                    ChatHighlightsSettingsView(highlightRules: $highlightRules)
                }
            }
        }
#else
        Form {
            LabeledContent("Substitute Emoji") {
                Toggle("", isOn: $substituteEmoji)
            }

            NavigationLink("Hightlights") {
                ChatHighlightsSettingsView(highlightRules: $highlightRules)
            }
        }
#endif
    }
}

struct ChatHighlightsSettingsView: View {
    @Binding var highlightRules: [ChatHighlightRule]
    @State private var pendingDeleteRuleID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                if highlightRules.isEmpty {
                    Text("No highlights yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($highlightRules) { $rule in
                        HStack(spacing: 10) {
                            TextField("Keyword", text: $rule.keyword)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 180)

                            ColorPicker(
                                "",
                                selection: Binding(
                                    get: { rule.color.swiftUIColor },
                                    set: { rule.color = CodableColor(swiftUIColor: $0) }
                                ),
                                supportsOpacity: true
                            )
                            .labelsHidden()
                            .frame(width: 42)

                            Spacer(minLength: 8)

                            HStack(spacing: 10) {
                                Text(previewText(for: rule.keyword))
                                    .lineLimit(1)
                                    .messageBubbleStyle(
                                        isFromYou: false,
                                        customFillColor: rule.color.swiftUIColor,
                                        customForegroundColor: rule.color.contrastTextColor
                                    )
                                    .frame(maxWidth: 360, alignment: .trailing)

                                Button(role: .destructive) {
                                    pendingDeleteRuleID = rule.id
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                            dimensions.width
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Hightlights")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    highlightRules.append(.defaultRule)
                } label: {
                    Label("Add Highlight", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            "Delete Highlight?",
            isPresented: Binding(
                get: { pendingDeleteRuleID != nil },
                set: { if !$0 { pendingDeleteRuleID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteRuleID {
                    removeRule(withID: id)
                }
                pendingDeleteRuleID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRuleID = nil
            }
        } message: {
            if let id = pendingDeleteRuleID,
               let rule = highlightRules.first(where: { $0.id == id })
            {
                let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if keyword.isEmpty {
                    Text("This highlight has no keyword. Do you want to delete it?")
                } else {
                    Text("Do you want to delete the highlight for \"\(keyword)\"?")
                }
            } else {
                Text("Do you want to delete this highlight?")
            }
        }
    }

    private func removeRule(withID id: UUID) {
        highlightRules.removeAll { $0.id == id }
    }

    private func previewText(for keyword: String) -> AttributedString {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = value.isEmpty ? "keyword" : value
        return AttributedString("Preview: this chat message contains \(sample).")
    }
}

struct FilesSettingsView: View {
    @AppStorage("DownloadPath") var downloadPath: String = NSHomeDirectory().stringByAppendingPathComponent(path: "Downloads")

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Downloads") {
                SettingsRow("Download Folder") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: downloadPath))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text((downloadPath as NSString).lastPathComponent)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Button("Change...") {
                            showFolderPicker()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
#else
        Text(downloadPath)
#endif
    }

#if os(macOS)
    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: downloadPath)

        if panel.runModal() == .OK, let url = panel.url {
            downloadPath = url.path
        }
    }
#endif
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
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Volume") {
                    SettingsRow("Volume", icon: "speaker.wave.2.fill") {
                        HStack(spacing: 10) {
                            Slider(
                                value: Binding(
                                    get: { eventsVolume },
                                    set: { eventsVolume = $0 }
                                ),
                                in: 0.0 ... 1.0
                            )
                            .frame(width: 200)

                            Text("\(Int((eventsVolume * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Event Configuration")
                        .font(.headline)
                        .foregroundStyle(.secondary)

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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
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


// MARK: - macOS System Settings-style reusable components

#if os(macOS)

/// A rounded-rect card container with an optional header title,
/// matching the macOS Ventura+ System Settings appearance.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// A single row inside a SettingsSection: label on the left, controls on the right.
struct SettingsRow<Content: View>: View {
    let label: String
    let icon: String?
    let alignment: VerticalAlignment
    @ViewBuilder let content: Content

    init(
        _ label: String,
        icon: String? = nil,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.icon = icon
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            Text(label)
            Spacer(minLength: 8)
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// A reusable "push" row for nested settings pages in the detail NavigationStack.
struct SettingsNavigationRow<Trailing: View, Destination: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let destination: Destination

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.trailing = trailing()
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                trailing
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A thin divider inset from the leading edge, matching Apple's in-card divider style.
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

#endif
