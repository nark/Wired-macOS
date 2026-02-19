//
//  SocketClient.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import Foundation
import KeychainSwift
@preconcurrency import WiredSwift
import SocketSwift

actor SocketClient {
    @AppStorage("UserNick") var userNick: String = "Wired Swift"
    @AppStorage("UserStatus") var userStatus = ""
    @AppStorage("UserIcon") var userIcon: String?
    
    private var connections: [UUID: WiredSwift.AsyncConnection] = [:]
    private var continuations: [UUID: AsyncThrowingStream<SocketEvent, Error>.Continuation] = [:]
    private var delegates: [UUID: DelegateProxy] = [:] // 🔑 rétention
        
    // MARK: - Connect

    func connect(
        configuration: ConnectionConfiguration
    ) -> AsyncThrowingStream<SocketEvent, Error> {

        let id = configuration.id
        let baseURL = configuration.url

        return AsyncThrowingStream { continuation in
            continuations[id] = continuation

            let proxy = DelegateProxy(
                id: id
            ) { [weak self] event in
                Task {
                    await self?.emit(event)
                }
            }

            let connection = WiredSwift.AsyncConnection(
                withSpec: spec!,
                delegate: proxy
            )
            
            connection.nick = userNick
            connection.status = userStatus
            connection.clientInfoDelegate = proxy
            connection.serverInfoDelegate = proxy
            if let userIcon = userIcon {
                connection.icon = userIcon
            }
            
            connections[id] = connection
            delegates[id] = proxy

            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect(id: id) }
            }
            
            let cipher      = configuration.cipher
            let compression = configuration.compression
            let checksum    = configuration.checksum
            let password    = configuration.password

            DispatchQueue.global().async {
                let url = baseURL
                if let password, !password.isEmpty {
                    url.password = password
                } else {
                    url.password = KeychainSwift().get("\(url.login)@\(url.hostname)") ?? ""
                }
               
                do {
                    try connection.connect(
                        withUrl: url,
                        cipher: cipher,
                        compression: compression,
                        checksum: checksum
                    )
                } catch {
                    print("catch connect error \(error.localizedDescription)")
                    if let se = error as? SocketSwift.Socket.Error {
                        print("se \(se)")
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Emit

    public func emit(_ event: SocketEvent) {
        guard let continuation = continuations[event.id] else { return }
        continuation.yield(event)
    }

    // MARK: - Send

    func send(_ message: P7Message, on id: UUID) async throws -> P7Message? {
        guard let connection = connections[id] else { return nil }
        let response:P7Message? = try await connection.sendAsync(message)
        return response
    }

    // MARK: - Disconnect

    func disconnect(id: UUID) {
        connections[id]?.disconnect()
        connections[id] = nil
        delegates[id] = nil          // 🔥 libération delegate
        continuations[id]?.finish()
        continuations[id] = nil
    }
}
