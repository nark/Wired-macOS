//
//  TransfersView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 14/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct TransfersView: View {
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager
    @State private var selection: Set<UUID> = []
    @State private var showRemoveConfirmation: Bool = false
    @State private var pendingRemovalTransferIDs: [UUID] = []
    
    var body: some View {
        VStack(spacing: 0) {
            transferList
                .onChange(of: transfers.transfers.map(\.id)) { _, currentIDs in
                    let validIDs = Set(currentIDs)
                    selection = selection.intersection(validIDs)
                }
                .alternatingRowBackgrounds()
                .alert(
                    "Remove transfer?",
                    isPresented: $showRemoveConfirmation,
                    presenting: pendingRemovalTransferIDs.count
                ) { count in
                    Button("Cancel", role: .cancel) {
                        pendingRemovalTransferIDs = []
                    }
                    Button(count > 1 ? "Remove Transfers" : "Remove Transfer", role: .destructive) {
                        confirmRemove()
                    }
                } message: { count in
                    Text(count > 1
                         ? "Are you sure you want to remove these \(count) transfers?"
                         : "Are you sure you want to remove this transfer?")
                }
            
            Divider()
            
            HStack {
                Button {
                    transfers.clear()
                    selection = selection.intersection(Set(transfers.transfers.map(\.id)))
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Clear finished transfers")

                Divider()
                    .frame(height: 16)

                Button {
                    applyToSelection { transfers.start($0) }
                } label: {
                    Image(systemName: "play")
                }
                .disabled(!canStartSelection)
                .help("Play transfer")
                
                Button() {
                    applyToSelection { transfers.pause($0) }
                } label: {
                    Image(systemName: "pause")
                }
                .disabled(!canPauseSelection)
                .help("Pause transfer")
                
                Button {
                    applyToSelection { transfers.stop($0) }
                } label: {
                    Image(systemName: "stop")
                }
                .disabled(!canStopSelection)
                .help("Stop transfer")
                
                Button {
                    requestRemove(selectedTransfers)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selection.isEmpty)
                .help("Remove transfer")
                
                Divider()
                    .frame(height: 16)
                
                Button {
                    showDownloadsInFinder(selectedTransfers)
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(!canShowFinderSelection)
                .help("Show in Finder")
                
                Button {
                    showRemoteLocation(selectedTransfers)
                } label: {
                    Image(systemName: "network")
                }
                .disabled(!canShowRemoteSelection)
                .help("Show Remote Location")
                
                Spacer()
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var transferList: some View {
        #if os(macOS)
        List(selection: $selection) {
            transferRows
        }
        #else
        List {
            transferRows
        }
        #endif
    }

    private var transferRows: some View {
        ForEach(transfers.transfers) { transfer in
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: transfer.type == .download ? "arrow.down.square.fill" : "arrow.up.square.fill")
                        .foregroundStyle(transfer.type == .download ? .blue : .red)

                    TransferItemIconView(transfer: transfer, size: 16)
                    
                    Text(transfer.name)
                    
                    Spacer()

//                            if transfer.hasError {
//                                Button {
//                                    errorAlertTitle = "Transfer Error"
//                                    errorAlertMessage = transfer.error
//                                    showErrorAlert = true
//                                } label: {
//                                    Image(systemName: "exclamationmark.triangle.fill")
//                                        .foregroundStyle(.yellow)
//                                }
//                                .buttonStyle(.plain)
//                                .help(transfer.error)
//                            }
                    
                    Text(serverName(for: transfer))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: transfer.percent, total: 100)
                
                HStack {
                    Text(transferStatusText(for: transfer))
                        .font(.caption)
                        .foregroundColor(transferStatusColor(for: transfer))
                        .lineLimit(2)
                    
                    Spacer()
                }

//                        if transfer.hasError {
//                            HStack {
//                                Text(transfer.error)
//                                    .font(.caption2)
//                                    .foregroundColor(.red)
//                                    .lineLimit(2)
//                                Spacer()
//                            }
//                        }
            }
            .contextMenu {
                let targets = actionTargets(for: transfer)

                Button("Start") { start(targets) }
                    .disabled(!canStart(targets))

                Button("Pause") { pause(targets) }
                    .disabled(!canPause(targets))

                Button("Stop") { stop(targets) }
                    .disabled(!canStop(targets))

                Button("Remove") { requestRemove(targets) }
                    .disabled(targets.isEmpty)

                Divider()

                Button("Show in Finder") { showDownloadsInFinder(targets) }
                    .disabled(!canShowFinder(targets))

                Button("Show Remote Location") { showRemoteLocation(targets) }
                    .disabled(!canShowRemote(targets))
            }
        }
    }

    private var selectedTransfers: [Transfer] {
        transfers.transfers.filter { selection.contains($0.id) }
    }

    private var canStartSelection: Bool {
        selectedTransfers.contains {
            $0.state == .locallyQueued || $0.state == .paused || $0.state == .stopped || $0.state == .disconnected
        }
    }

    private var canPauseSelection: Bool {
        canPause(selectedTransfers)
    }

    private var canStopSelection: Bool {
        canStop(selectedTransfers)
    }

    private var canShowFinderSelection: Bool {
        canShowFinder(selectedTransfers)
    }

    private var canShowRemoteSelection: Bool {
        canShowRemote(selectedTransfers)
    }

    private func applyToSelection(_ action: (Transfer) -> Void) {
        for transfer in selectedTransfers {
            action(transfer)
        }
    }

    private func actionTargets(for clickedTransfer: Transfer) -> [Transfer] {
        if selection.contains(clickedTransfer.id) {
            return selectedTransfers
        }
        return [clickedTransfer]
    }

    private func canPause(_ items: [Transfer]) -> Bool {
        items.contains { $0.isWorking() || $0.state == .locallyQueued }
    }

    private func canStop(_ items: [Transfer]) -> Bool {
        items.contains { $0.isWorking() || $0.state == .locallyQueued }
    }

    private func canStart(_ items: [Transfer]) -> Bool {
        items.contains {
            $0.state == .locallyQueued || $0.state == .paused || $0.state == .stopped || $0.state == .disconnected
        }
    }

    private func canShowFinder(_ items: [Transfer]) -> Bool {
        items.contains { $0.localPath?.isEmpty == false }
    }

    private func canShowRemote(_ items: [Transfer]) -> Bool {
        items.contains { ($0.remotePath?.isEmpty == false) && $0.connectionID != nil }
    }

    private func transferStatusText(for transfer: Transfer) -> String {
        let error = transfer.error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty && (transfer.state == .stopped || transfer.state == .disconnected) {
            return error
        }
        return transfer.transferStatus()
    }

    private func transferStatusColor(for transfer: Transfer) -> Color {
        let error = transfer.error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty && (transfer.state == .stopped || transfer.state == .disconnected) {
            return .red
        }
        return .secondary
    }

    private func serverName(for transfer: Transfer) -> String {
        if let connectionID = transfer.connectionID,
           let runtime = connectionController.runtime(for: connectionID),
           let serverInfo = runtime.connection?.serverInfo {
            let trimmedServerName = serverInfo.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedServerName.isEmpty {
                return trimmedServerName
            }
        }

        if let uri = transfer.uri,
           let host = URLComponents(string: uri)?.host,
           !host.isEmpty {
            return host
        }

        return "Unknown Server"
    }

    private func start(_ items: [Transfer]) {
        for transfer in items { transfers.start(transfer) }
    }

    private func pause(_ items: [Transfer]) {
        for transfer in items { transfers.pause(transfer) }
    }

    private func stop(_ items: [Transfer]) {
        for transfer in items { transfers.stop(transfer) }
    }

    private func remove(_ items: [Transfer]) {
        for transfer in items { transfers.remove(transfer) }
        selection = selection.intersection(Set(transfers.transfers.map(\.id)))
    }

    private func requestRemove(_ items: [Transfer]) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return }
        pendingRemovalTransferIDs = ids
        showRemoveConfirmation = true
    }

    private func confirmRemove() {
        let idSet = Set(pendingRemovalTransferIDs)
        let items = transfers.transfers.filter { idSet.contains($0.id) }
        remove(items)
        pendingRemovalTransferIDs = []
    }

    private func showDownloadsInFinder(_ items: [Transfer]) {
        #if os(macOS)
        let urls = items.compactMap { transfer -> URL? in
            guard let localPath = transfer.localPath, !localPath.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: localPath)
        }
        guard !urls.isEmpty else { return }

        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existingURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(existingURLs)
            return
        }

        let folders = Set(urls.map { $0.deletingLastPathComponent() })
        for folder in folders {
            NSWorkspace.shared.open(folder)
        }
        #endif
    }

    private func showRemoteLocation(_ items: [Transfer]) {
        for transfer in items {
            guard transfer.type == .upload,
                  let connectionID = transfer.connectionID,
                  let remotePath = transfer.remotePath,
                  !remotePath.isEmpty else { continue }

            if let runtime = connectionController.runtime(for: connectionID) {
                runtime.selectedTab = .files
            }

            NotificationCenter.default.post(
                name: .revealRemoteTransferPath,
                object: RemoteTransferPathRequest(connectionID: connectionID, path: remotePath)
            )
        }
    }
}

private struct TransferItemIconView: View {
    let transfer: Transfer
    let size: CGFloat

    var body: some View {
        #if os(macOS)
        Image(nsImage: iconImage())
            .resizable()
            .frame(width: size, height: size)
        #else
        Image(systemName: transfer.isFolder ? "folder" : "document")
            .font(.system(size: size * 0.7))
        #endif
    }

    #if os(macOS)
    private func iconImage() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFileType: fileTypeIdentifier())
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private func fileTypeIdentifier() -> String {
        if transfer.isFolder {
            return UTType.folder.identifier
        }

        let name = (transfer.name as NSString)
        let ext = name.pathExtension
        if ext.isEmpty {
            return UTType.data.identifier
        }
        return ext
    }
    #endif
}
