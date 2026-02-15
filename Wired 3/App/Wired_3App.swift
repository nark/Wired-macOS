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


@main
struct Wired_3App: App {
    @State private var socketClient = SocketClient()
    @State private var controller: ConnectionController
    @State private var transfers: TransferManager
    
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
        WindowGroup {
            AppRootView()
                .environment(controller)
                .environmentObject(transfers)
        }
        .modelContainer(sharedModelContainer)
        
#if os(macOS)
        Settings {
            SettingsView()
        }
#endif
    }
}

/// A small root view that has access to SwiftData's ModelContext.
/// This avoids threading ModelContext manually through your whole view tree.
private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var transfers: TransferManager

    var body: some View {
        MainView()
            .onAppear {
                // Attach SwiftData once, and restore persisted transfers.
                transfers.attach(modelContext: modelContext)

                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.badge, .alert, .sound]
                ) { granted, _ in
                    print("Notifications permission:", granted)
                }
            }
#if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                transfers.prepareForTermination()
            }
#endif
    }
}
