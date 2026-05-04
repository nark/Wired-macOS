//
//  User.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

enum UserActiveTransferType: UInt32 {
    case download = 0
    case upload = 1

    var title: String {
        switch self {
        case .download: return "Download"
        case .upload: return "Upload"
        }
    }
}

struct UserActiveTransfer {
    let type: UserActiveTransferType
    let path: String
    let dataSize: UInt64
    let rsrcSize: UInt64
    let transferred: UInt64
    let speed: UInt32
    let queuePosition: Int

    var totalSize: UInt64 {
        dataSize + rsrcSize
    }

    var isQueued: Bool {
        queuePosition > 0
    }

    var stateDescription: String {
        isQueued ? "Queued at position \(queuePosition)" : "Running"
    }

    var displaySnapshot: TransferDisplaySnapshot {
        TransferDisplaySnapshot(
            typeTitle: type.title,
            path: path,
            transferredBytes: transferred,
            totalBytes: totalSize,
            speedBytesPerSecond: Double(speed),
            queuePosition: queuePosition,
            statusText: TransferDisplaySnapshot.makeRemoteStatus(
                transferredBytes: transferred,
                totalBytes: totalSize,
                speedBytesPerSecond: Double(speed),
                queuePosition: queuePosition
            ),
            isErrorStatus: false
        )
    }
}

struct MonitoredUser: Identifiable {
    let id: UInt32
    let nick: String
    let status: String?
    let icon: Data
    let idle: Bool
    let color: UInt32
    let idleTime: Date?
    let activeTransfer: UserActiveTransfer?

    var isDownloading: Bool {
        activeTransfer?.type == .download
    }

    var isUploading: Bool {
        activeTransfer?.type == .upload
    }

    var transferSpeed: UInt64 {
        UInt64(activeTransfer?.speed ?? 0)
    }
}

struct TransferDisplaySnapshot {
    let typeTitle: String
    let path: String
    let transferredBytes: UInt64
    let totalBytes: UInt64
    let speedBytesPerSecond: Double
    let queuePosition: Int
    let statusText: String
    let isErrorStatus: Bool

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(transferredBytes) / Double(totalBytes)))
    }

    var progressText: String {
        "\(Self.formatBytes(transferredBytes)) / \(Self.formatBytes(totalBytes))"
    }

    var speedText: String? {
        guard speedBytesPerSecond > 0 else { return nil }
        return "\(Self.formatBytes(UInt64(speedBytesPerSecond.rounded()))) / s"
    }

    static func formatBytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(value))
    }

    static func makeRemoteStatus(
        transferredBytes: UInt64,
        totalBytes: UInt64,
        speedBytesPerSecond: Double,
        queuePosition: Int
    ) -> String {
        if queuePosition > 0 {
            return "Queued at position \(queuePosition)"
        }

        let transferredString = formatBytes(transferredBytes)
        let totalString = formatBytes(totalBytes)

        guard speedBytesPerSecond > 0, totalBytes > transferredBytes else {
            return "\(transferredString) of \(totalString)"
        }

        let remaining = totalBytes - transferredBytes
        let etaSeconds = Double(remaining) / speedBytesPerSecond
        let speedString = formatBytes(UInt64(speedBytesPerSecond.rounded()))

        return "\(transferredString) of \(totalString), \(speedString)/s, \(formatDuration(etaSeconds))"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }
}

@Observable
@MainActor
final class OfflineUser: Identifiable {
    let login: String
    var nick: String

    var id: String { login }

    init(login: String, nick: String? = nil) {
        self.login = login
        self.nick = nick ?? login
    }
}

@Observable
@MainActor
final class User: Identifiable {
    let id: UInt32
    var nick: String
    var status: String?
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
    var activeTransfer: UserActiveTransfer?

    init(id: UInt32, nick: String, status: String? = nil, icon: Data, idle: Bool) {
        self.id = id
        self.nick = nick
        self.icon = icon
        self.idle = idle
        self.status = status
    }
}
