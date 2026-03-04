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
    var body: some View {
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
#if os(macOS)
        .scenePadding()
        .frame(minWidth: 620, minHeight: 500)
#endif
    }
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
    @AppStorage(WiredEventsStore.volumeKey) private var eventsVolume: Double = 1.0
    @AppStorageCodable(
        key: WiredEventsStore.configurationsKey,
        defaultValue: WiredEventsStore.defaultConfigurations()
    )
    private var configurations: [WiredEventConfiguration]

    @State private var selectedTag: WiredEventTag = .serverConnected

    var body: some View {
        ScrollView {
            Form {
                LabeledContent("Volume") {
                    Slider(
                        value: Binding(
                            get: { eventsVolume },
                            set: { eventsVolume = $0 }
                        ),
                        in: 0.0 ... 1.0
                    )
                    .frame(width: 260)
                }

                LabeledContent("Event") {
                    Picker("Event", selection: $selectedTag) {
                        ForEach(WiredEventTag.menuOrder) { tag in
                            Text(eventMenuTitle(for: tag))
                                .tag(tag)
                            if tag == .error || tag == .boardPostAdded {
                                Divider()
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 320)
                }

                Divider()

                LabeledContent("Play Sound") {
                    Toggle("", isOn: binding(\.playSound))
                        .onChange(of: currentConfiguration.playSound) { _, enabled in
                            if enabled {
                                playPreviewSound()
                            }
                        }
                }

                LabeledContent("Sound") {
                    Picker("Sound", selection: binding(\.sound).nonOptional(defaultValue: WiredEventsStore.defaultSoundName)) {
                        ForEach(WiredEventsStore.availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .disabled(!currentConfiguration.playSound)
                    .onChange(of: currentConfiguration.sound) { _, _ in
                        if currentConfiguration.playSound {
                            playPreviewSound()
                        }
                    }
                }

                LabeledContent("Bounce In Dock") {
                    Toggle("", isOn: binding(\.bounceInDock))
                }

                LabeledContent("Post In Chat") {
                    Toggle("", isOn: binding(\.postInChat))
                        .disabled(!supportsPostInChat)
                }

                LabeledContent("Show Alert") {
                    // TODO: Hook this toggle to a real in-app alert path once legacy WCEventsShowDialog behavior is restored.
                    Toggle("", isOn: binding(\.showAlert))
                        .disabled(!supportsShowAlert)
                }

                LabeledContent("Notification Center") {
                    Toggle("", isOn: binding(\.notificationCenter))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private var currentConfiguration: WiredEventConfiguration {
        configurations.first(where: { $0.tag == selectedTag }) ?? WiredEventConfiguration(tag: selectedTag)
    }

    private var supportsPostInChat: Bool {
        switch selectedTag {
        case .userJoined, .userChangedNick, .userChangedStatus, .userLeft:
            return true
        default:
            return false
        }
    }

    private var supportsShowAlert: Bool {
        switch selectedTag {
        case .messageReceived, .broadcastReceived:
            return true
        default:
            return false
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WiredEventConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: {
                currentConfiguration[keyPath: keyPath]
            },
            set: { newValue in
                var all = normalized(configurations)
                if let index = all.firstIndex(where: { $0.tag == selectedTag }) {
                    all[index][keyPath: keyPath] = newValue
                } else {
                    var config = WiredEventConfiguration(tag: selectedTag)
                    config[keyPath: keyPath] = newValue
                    all.append(config)
                }
                configurations = normalized(all)
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

    private func eventMenuTitle(for tag: WiredEventTag) -> String {
        let hasSound = configurations.first(where: { $0.tag == tag })?.playSound ?? false
        return hasSound ? "\(tag.title)  🔊" : tag.title
    }

    private func playPreviewSound() {
#if os(macOS)
        let soundName = currentConfiguration.sound ?? WiredEventsStore.defaultSoundName
        guard let sound = NSSound(named: NSSound.Name(soundName)) else { return }
        sound.volume = Float(max(0.0, min(eventsVolume, 1.0)))
        sound.play()
#endif
    }
}

private extension Binding where Value == String? {
    func nonOptional(defaultValue: String) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? defaultValue },
            set: { wrappedValue = $0 }
        )
    }
}
