//
//  ConnectionState.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

@Observable
@MainActor
final class ConnectionState: Identifiable {
    let id: UUID
    var status: Status = .disconnected
    var lastError: Error?
    
    init(id: UUID, status: Status, lastError: Error? = nil) {
        self.id = id
        self.status = status
        self.lastError = lastError
    }

    enum Status {
        case disconnected, connecting, connected
    }
}
