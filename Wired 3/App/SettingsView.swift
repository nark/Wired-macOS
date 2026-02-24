//
//  SettingsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import DebouncedOnChange

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
        }
#if os(macOS)
        .scenePadding()
        .frame(maxWidth: 350, minHeight: 150)
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
