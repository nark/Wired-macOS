//
//  User.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//


import SwiftUI

@Observable
@MainActor
final class User: Identifiable {
    let id: UInt32
    var nick: String
    var status: String = ""
    var icon: Data
    var idle: Bool = false
    var color: UInt32 = 0
    
    var appVersion: String = ""
    var appBuild: String = ""
    var osName: String = ""
    var osVersion: String = ""
    var arch: String = ""
    var supportsRsrc: String = ""
    
    var login: String = ""
    var ipAddress: String = ""
    var host: String = ""
    var cipherName: String = ""
    var cipherBits: String = ""
    var loginTime: Date?
    var idleTime: Date?
    
    init(id: UInt32, nick: String, status: String = "", icon: Data, idle: Bool) {
        self.id = id
        self.nick = nick
        self.icon = icon
        self.idle = idle
        self.status = status
    }
}
