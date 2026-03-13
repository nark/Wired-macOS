//
//  DelegateProxy.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

final class DelegateProxy: NSObject, ConnectionDelegate, ClientInfoDelegate, ServerInfoDelegate {
    let id: UUID
    private let onEvent: (SocketEvent) -> Void

    init(
        id: UUID,
        onEvent: @escaping (SocketEvent) -> Void
    ) {
        self.id = id
        self.onEvent = onEvent
    }

    // MARK: - ConnectionDelegate
    
    nonisolated func connectionDidConnect(connection: WiredSwift.Connection) {
        onEvent(.connected(id, connection))
    }
    
    func connectionDidFailToConnect(connection: Connection, error: any Error) {
        onEvent(.disconnected(id, connection, error))
    }
    
    func connectionDidLogin(connection: Connection, message: P7Message) {
        onEvent(.received(id, connection, message))
    }
    
    func connectionDidReceivePriviledges(connection: Connection, message: P7Message) {
        onEvent(.received(id, connection, message))
    }
    
    func connectionDisconnected(connection: Connection, error: (any Error)?) {
        onEvent(.disconnected(id, connection, error))
    }
    
    nonisolated func connectionDidReceiveMessage(connection: WiredSwift.Connection, message: WiredSwift.P7Message) {
        onEvent(.received(id, connection, message))
    }
    
    nonisolated func connectionDidReceiveError(connection: WiredSwift.Connection, message: WiredSwift.P7Message) {
        print("connectionDidReceiveError")
        onEvent(.received(id, connection as! AsyncConnection, message))
    }
    
    // MARK: -
    
    func clientInfoApplicationName(for connection: Connection) -> String? {
        return Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
    }
    
    func clientInfoApplicationVersion(for connection: Connection) -> String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    func clientInfoApplicationBuild(for connection: Connection) -> String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    // MARK: -
    
    func serverInfoDidChange(for connection: Connection) {
        onEvent(.serverInfoChanged(id, connection))
    }
}
