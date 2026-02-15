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
    /// Creation date used to restore a stable order across launches.
    var createdDate: Date = Date()
    var name: String = ""
    var uri: String?
    /// Persisted identifier of the control connection used to start this transfer.
    /// Used to resolve `connection` again after app relaunch.
    var connectionID: UUID?
    var isFolder: Bool = false
    var localPath: String?
    var remotePath: String?
    var dataTransferred: Int64 = 0
    var rsrcTransferred: Int64 = 0
    var actualTransferred: Int64 = 0
    /// Position reported by the server via `wired.transfer.queue`.
    /// 0 means "ready" (slot acquired server-side).
    var queuePosition: Int = 0

    /// Folder progress
    var totalFiles: Int = 1
    var transferredFiles: Int = 0
    var createdDirectories: Int = 0
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
    /// For folder transfers, the worker updates this to point to the currently processed local file.
    @Transient var currentLocalFilePath: String? = nil
    @Transient var speedCalculator:SpeedCalculator = SpeedCalculator()
    
    init(name: String, type: TransferType, connection: AsyncConnection? = nil) {
        self.id = UUID()
        self.createdDate = Date()
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
        // WCTransfers-like status formatting
        let transferredBytes = dataTransferred + rsrcTransferred
        let sizeBytes = max(size, 0)
        let remaining = transferredBytes < sizeBytes ? sizeBytes - transferredBytes : 0
        let etaSeconds: Double = (speed > 0) ? Double(remaining) / speed : 0

        let transferredString = byteCountFormatter.string(fromByteCount: transferredBytes)
        let sizeString = byteCountFormatter.string(fromByteCount: sizeBytes)
        let speedString = byteCountFormatter.string(fromByteCount: Int64(speed.rounded()))
        let etaString = TimeInterval(etaSeconds).stringFromTimeInterval()
        let tookString = TimeInterval(accumulatedTime).stringFromTimeInterval()

        func folderPrefix() -> String {
            if isFolder && totalFiles > 1 {
                return "\(transferredFiles) of \(totalFiles) files, "
            }
            return ""
        }

        switch state {
        case .locallyQueued:
            return "Queued"

        case .waiting:
            return "Waiting"

        case .queued:
            return queuePosition > 0
                ? "Queued at position \(queuePosition)"
                : "Queued"

        case .listing:
            return "Listing directory... \(totalFiles) \(totalFiles == 1 ? "file" : "files")"

        case .creatingDirectories:
            return "Creating directories... \(createdDirectories)"

        case .running:
            return "\(folderPrefix())\(transferredString) of \(sizeString), \(speedString)/s, \(etaString)"

        case .pausing:
            return "Pausing…"

        case .stopping:
            return "Stopping…"

        case .disconnecting:
            return "Disconnecting…"

        case .removing:
            return "Removing…"

        case .paused, .stopped, .disconnected:
            let verb = (state == .paused) ? "Paused" : (state == .stopped ? "Stopped" : "Disconnected")
            if isFolder && totalFiles > 1 {
                return "\(verb) at \(transferredFiles) of \(totalFiles) files, \(transferredString) of \(sizeString)"
            } else {
                return "\(verb) at \(transferredString) of \(sizeString)"
            }

        case .finished:
            // User request: show total transfer time when finished.
            let avgSpeed: Double = accumulatedTime > 0 ? Double(actualTransferred) / accumulatedTime : 0
            let avgSpeedString = byteCountFormatter.string(fromByteCount: Int64(avgSpeed.rounded()))
            if isFolder && totalFiles > 1 {
                return "Finished \(transferredFiles) files, average \(avgSpeedString)/s, took \(tookString)"
            } else {
                return "Finished \(transferredString), average \(avgSpeedString)/s, took \(tookString)"
            }
        }
    }
}
