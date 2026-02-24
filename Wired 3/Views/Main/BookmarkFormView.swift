//
//  BookmarkFormView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import KeychainSwift
import WiredSwift

struct BookmarkFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    @State var name: String = ""
    @State var hostname: String = ""
    @State var login: String = ""
    @State var password: String = ""
    
    @State var connectAtStartup: Bool = false
    @State var autoReconnect: Bool = false
    
    @State var cipher: UInt32 = P7Socket.CipherType.ECDH_CHACHA20_POLY1305.rawValue
    @State var checksum: UInt32 = P7Socket.Checksum.HMAC_256.rawValue
    @State var compression: UInt32 = P7Socket.Compression.LZ4.rawValue
    
    var bookmark: Bookmark? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                
                Section {
                    TextField("Hostname", text: $hostname)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                    
                    TextField("Login", text: $login)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                    
                    SecureField("Password", text: $password)
                } header: {
                    Text("Authentication")
                }
                
                Section {
                    Toggle("Connect At Startup", isOn: $connectAtStartup)
                    Toggle("Auto-reconnect when disconnected", isOn: $autoReconnect)
                }
                
                Section {
                    Picker("Encryption", selection: $cipher) {
                        ForEach([
                            P7Socket.CipherType.NONE,
                            P7Socket.CipherType.ECDH_AES256_SHA256,
                            P7Socket.CipherType.ECDH_AES128_GCM,
                            P7Socket.CipherType.ECDH_AES256_GCM,
                            P7Socket.CipherType.ECDH_CHACHA20_POLY1305,
                            P7Socket.CipherType.ECDH_XCHACHA20_POLY1305
                            
                        ], id: \.rawValue) { c in
                            Text(c.description).tag(c.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Compression", selection: $compression) {
                        ForEach([
                            P7Socket.Compression.NONE,
                            P7Socket.Compression.DEFLATE,
                            P7Socket.Compression.LZFSE,
                            P7Socket.Compression.LZ4
                        ], id: \.rawValue) { c in
                            Text(c.description).tag(c.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Checksum", selection: $checksum) {
                        ForEach([
                            P7Socket.Checksum.NONE,
                            P7Socket.Checksum.SHA2_256,
                            P7Socket.Checksum.SHA2_384,
                            P7Socket.Checksum.SHA3_256,
                            P7Socket.Checksum.SHA3_384,
                            P7Socket.Checksum.HMAC_256,
                            P7Socket.Checksum.HMAC_384
                        ], id: \.rawValue) { c in
                            Text(c.description).tag(c.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Security")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text("Save")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            let keychain = KeychainSwift()
            
            if let bookmark {
                name = bookmark.name
                hostname = bookmark.hostname
                login = bookmark.login
                connectAtStartup = bookmark.connectAtStartup
                autoReconnect = bookmark.autoReconnect
                compression = bookmark.compressionRawValue
                checksum = bookmark.checksumRawValue
                cipher = bookmark.cipherRawValue
                password = keychain.get("\(login)@\(hostname)") ?? ""
            }
        }
    }
    
    func save() {
        let keychain = KeychainSwift()
        
        if let bookmark {
            bookmark.name = name
            bookmark.hostname = hostname
            bookmark.login = login
            bookmark.connectAtStartup = connectAtStartup
            bookmark.autoReconnect = autoReconnect
            bookmark.compressionRawValue = compression
            bookmark.cipherRawValue = cipher
            bookmark.checksumRawValue = checksum
            
            try? modelContext.save()
            
        } else {
            let newBookmark = Bookmark(name: name, hostname: hostname, login: login)
            newBookmark.connectAtStartup = connectAtStartup
            newBookmark.autoReconnect = autoReconnect
            newBookmark.cipherRawValue = cipher
            newBookmark.compressionRawValue = compression
            newBookmark.checksumRawValue = checksum
            
            modelContext.insert(newBookmark)
        }
        
        keychain.set(password, forKey: "\(login)@\(hostname)")
        
        dismiss()
    }
}

struct NewConnectionFormView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(\.dismiss) private var dismiss

    @State private var hostname: String = ""
    @State private var login: String = ""
    @State private var password: String = ""

    let draft: NewConnectionDraft
    let onConnected: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Hostname:Port", text: $hostname)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif

                    TextField("Login", text: $login)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif

                    SecureField("Password", text: $password)
                } header: {
                    Text("Connection")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        connect()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Connection")
        }
        .onAppear {
            hostname = draft.hostname
            login = draft.login
            password = draft.password
        }
    }

    private func connect() {
        let normalized = NewConnectionDraft(
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
            login: login.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        guard let id = connectionController.connectTemporary(normalized, requestSelection: false) else { return }
        connectionController.presentedNewConnection = nil
        dismiss()
        DispatchQueue.main.async {
            onConnected(id)
        }
    }
}
