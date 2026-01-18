//
//  TransferManager.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 11/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

@MainActor
final class TransferManager: ObservableObject {
    @Published private(set) var transfers: [Transfer] = []

    private let spec: P7Spec
    private let connectionController: ConnectionController

    init(spec: P7Spec, connectionController: ConnectionController) {
        self.spec = spec
        self.connectionController = connectionController
    }
    
    // MARK: -

    /**
     Clear transfers with state .finished
     */
    func clear() {
        transfers.removeAll { $0.state == .finished }
    }
    
    
    // MARK: -
    
    func download(_ file: FileItem, with connectionID: UUID) {
        let downloadPath = TransferWorker.temporaryDownloadDestination(forPath: file.path)
        
        download(file, to: downloadPath, with: connectionID)
    }

    func download(_ file: FileItem, to destination: String, with connectionID: UUID) -> Bool  {
        guard let runtime = connectionController.runtime(for: connectionID) else { return false }
        guard let connection = runtime.connection as? AsyncConnection else { return false }

        let transfer = Transfer(
            name: file.name,
            type: .download,
            connection: connection
        )

        transfer.uri        = connection.URI
        transfer.remotePath = file.path
        transfer.localPath  = destination
        transfer.file       = file
        transfer.size       = Int64(file.dataSize)
        transfer.startDate  = Date()

        transfers.append(transfer)

        Task.detached {
            let worker = await TransferWorker(
                transfer: transfer,
                spec: self.spec
            )
            
            await worker.run()
        }
        
        return true
    }
    
    // MARK: -
    
    public func upload(_ path:String, toDirectory destination:FileItem, with connectionID: UUID, filesViewModel: FilesViewModel) -> Bool {
        guard let runtime = connectionController.runtime(for: connectionID) else { return false }
        guard let connection = runtime.connection as? AsyncConnection else { return false }
        
        let remotePath = destination.path.stringByAppendingPathComponent(path: path.lastPathComponent)
        
        let transfer = Transfer(
            name: path.lastPathComponent,
            type: .upload,
            connection: connection
        )
        
        var file = FileItem(path.lastPathComponent, path: remotePath)
        file.uploadDataSize = FileManager.sizeOfFile(atPath: path) ?? 0
        
        transfer.uri = connection.URI
        transfer.remotePath = remotePath
        transfer.localPath = path
        transfer.file = file
        transfer.size = Int64(file.uploadDataSize + file.uploadRsrcSize)
        transfer.startDate = Date()
        
        transfers.append(transfer)
        
        Task.detached {
            let worker = await TransferWorker(
                transfer: transfer,
                spec: self.spec
            )
            
            await worker.run()
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await filesViewModel.reloadSelectedColumn()
        }
        
        return true
    }
}
