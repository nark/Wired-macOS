//
//  TransfersView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 14/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TransfersView: View {
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager
    @State private var showErrorAlert: Bool = false
    @State private var errorAlertTitle: String = "Transfer Error"
    @State private var errorAlertMessage: String = ""
    @State private var selection: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            transferList
                .onChange(of: transfers.transfers.map(\.id)) { _, currentIDs in
                    let validIDs = Set(currentIDs)
                    selection = selection.intersection(validIDs)
                }
                .alternatingRowBackgrounds()
                .alert(errorAlertTitle, isPresented: $showErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(errorAlertMessage)
                }
            
            Divider()
            
            HStack {
                Button {
                    transfers.clear()
                    selection = selection.intersection(Set(transfers.transfers.map(\.id)))
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Clear finished transfers")

                Divider()
                    .frame(height: 16)

                Button("Start") {
                    applyToSelection { transfers.start($0) }
                }
                .disabled(!canStartSelection)

                Button("Pause") {
                    applyToSelection { transfers.pause($0) }
                }
                .disabled(!canPauseSelection)

                Button("Stop") {
                    applyToSelection { transfers.stop($0) }
                }
                .disabled(!canStopSelection)

                Button("Remove") {
                    applyToSelection { transfers.remove($0) }
                    selection = selection.intersection(Set(transfers.transfers.map(\.id)))
                }
                .disabled(selection.isEmpty)

                Button("Show in Finder") {
                    showDownloadsInFinder(selectedTransfers)
                }
                .disabled(!canShowFinderSelection)

                Button("Show Remote Location") {
                    showRemoteLocation(selectedTransfers)
                }
                .disabled(!canShowRemoteSelection)
                
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
                    
                    Text(transfer.uri ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: transfer.percent, total: 100)
                
                HStack {
                    Text(transfer.transferStatus())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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

                Button("Remove") { remove(targets) }
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
