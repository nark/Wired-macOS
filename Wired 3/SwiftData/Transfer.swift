//
//  Transfer.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import Foundation
import SwiftData
import WiredSwift

enum TransferType: String, Codable {
    case download
    case upload
}

enum TransferState: String, Codable {
    case waiting
    case locallyQueued
    case queued
    case listing
    case creatingDirectories
    case running
    case pausing
    case paused
    case stopping
    case stopped
    case disconnecting
    case disconnected
    case removing
    case finished
}

@Model
public final class Transfer {
    @Attribute(.unique) public var id: UUID
    var name: String = ""
    var uri: String?
    var isFolder: Bool = false
    var localPath: String?
    var remotePath: String?
    var dataTransferred: Int64 = 0
    var rsrcTransferred: Int64 = 0
    var actualTransferred: Int64 = 0
    var startDate: Date?
    var accumulatedTime: Double = 0
    var percent: Double = 0
    var speed: Double = 0
    var size: Int64 = 0
    var type: TransferType = TransferType.download
    var state: TransferState = TransferState.waiting
    var error:String = ""
    
    @Transient var connection: AsyncConnection? = nil
    @Transient var transferConnection: TransferConnection? = nil
    @Transient var file: FileItem? = nil
    @Transient var speedCalculator:SpeedCalculator = SpeedCalculator()
    
    init(name: String, type: TransferType, connection: AsyncConnection? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.connection = connection
    }
    
    public func isWorking() -> Bool {
        return (state == .waiting || state == .queued ||
                state == .listing || state == .creatingDirectories ||
                state == .running)
    }
    
    public func isTerminating() -> Bool {
        return (state == .pausing || state == .stopping ||
                state == .disconnecting || state == .removing)
    }

    public func isStopped() -> Bool {
        return (state == .paused || state == .stopped ||
                state == .disconnected || state == .finished)
    }
    
    public func transferStatus() -> String {
        let remaining = dataTransferred < size ? size - dataTransferred : 0
        let interval  = (speed > 0) ? Double(remaining) / speed : 0;
        
        let typeString      = type == .download ? "Download" : "Upload"
        let speedString     = byteCountFormatter.string(fromByteCount: Int64(speed.rounded()))
        let sizeString      = byteCountFormatter.string(fromByteCount: dataTransferred)
        let totalString     = byteCountFormatter.string(fromByteCount: size)
        let intervalString  = TimeInterval(exactly: interval)!.stringFromTimeInterval()
        
        let speed = NSLocalizedString("speed", comment: "")
        
        var s = "\(typeString) \(state), \(percent.rounded())%, \(speed) \(speedString)/s"
        
        if isWorking() {
            s = "\(typeString) \(state), \(sizeString) of \(totalString), \(percent.rounded())%, \(speed) \(speedString)/s, \(intervalString)"
        } else {
            s = "\(typeString) \(state), \(sizeString), \(speed) \(speedString)/s, \(intervalString)"
        }
        
        if error != "" {
            s = "\(s) - \(error)"
        }
        
        return s
    }
}
