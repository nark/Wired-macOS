//
//  TransferManager.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 11/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

actor TransferWorker {

    private let transfer: Transfer
    private let spec: P7Spec
    
    private let cipher: P7Socket.CipherType = .ECDH_CHACHA20_POLY1305
    private let compression: P7Socket.Compression = .LZFSE
    private let checksum: P7Socket.Checksum = .HMAC_256
    
    init(transfer: Transfer, spec: P7Spec) {
        self.transfer = transfer
        self.spec = spec
    }

    func run() async {
        do {
            switch transfer.type {
            case .download:
                try await runDownload(transfer)
            case .upload:
                try await runUpload(transfer)
            }
            
            self.finish(transfer)
            
        } catch {
            print("TransferWorker error \(error)")
        }
    }
    

    private func runDownload(_ transfer : Transfer) async throws {
        var data = true
        var dataLength:UInt64? = 0
        var rsrcLength:UInt64? = 0
        var time:Double = 0.0, speedTime:Double = 0.0
        var speedBytes:Int = 0
        
        if transfer.transferConnection == nil {
            transfer.transferConnection = self.transfertConnectionForTransfer(transfer)
        }
        
        transfer.transferConnection?.interactive = false
        
        guard let connection = transfer.transferConnection else {
            print("No transfer connection")
            return
        }
        
        guard let url = transfer.connection?.url else {
            print("No connection URL")
            return
        }
        
        // connect transfer connection
        try connection.connect(withUrl: url, cipher: cipher, compression: compression, checksum: checksum)
        
        speedTime = TransfersTimeInterval()
        transfer.speed = 0.0
        
        // send download message
        if !connection.send(message: downloadFileMessage(for: transfer)) {
            print("Cannot download file")
        }
                
        guard let runMessage = self.run(transfer.transferConnection!, forTransfer: transfer, untilReceivingMessageName: "wired.transfer.download") else {
            print("Terminating tranfer")
            
            if transfer.isTerminating() == false {
                transfer.state = .disconnecting
            }
            
            self.finish(transfer)
            
            return
        }
        
        dataLength = runMessage.uint64(forField: "wired.transfer.data")
        rsrcLength = runMessage.uint64(forField: "wired.transfer.rsrc")
        
        let dataPath = TransferWorker.temporaryDownloadDestination(forPath: transfer.remotePath!)
        let rsrcPath = FileManager.resourceForkPath(forPath: dataPath)
        
        print("OK here")
        
        transfer.speedCalculator.add(bytes: 0, time: 0)
        
        while(transfer.isTerminating() == false) {
            if data == true && dataLength == 0 {
                data = false
            }
            
            if data == false && rsrcLength == 0 {
                break
            }
            
            let oobdata = try transfer.transferConnection!.socket.readOOB(timeout: 30.0)
            
            if FileManager.default.fileExists(atPath: dataPath) {
                if let fileHandle = FileHandle(forWritingAtPath: dataPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(oobdata)
                    fileHandle.closeFile()
                } else {
                    DispatchQueue.main.async {
//                        let downloaderror = NSLocalizedString("Download Error", comment: "")
//                        error = WiredError(withTitle: downloaderror, message: "Transfer failed")
//
//                        Logger.error(error!)
                    }
                    break
                }
            } else {
                do {
                    try oobdata.write(to: URL(fileURLWithPath: data ? dataPath : rsrcPath), options: .atomicWrite)
                } catch let e {
                    DispatchQueue.main.async {
//                        let downloaderror = NSLocalizedString("Download Error", comment: "")
//                        let transferfailed = NSLocalizedString("Transfer failed", comment: "")
//                        error = WiredError(withTitle: downloaderror, message: transferfailed + " \(e)")
//
//                        Logger.error(error!)
                    }
                    
                    break
                }
            }
            
            if data {
                transfer.dataTransferred    += Int64(oobdata.count)
            } else {
                transfer.rsrcTransferred    += Int64(oobdata.count)
            }
            
            let totalTransferSize           = transfer.file!.dataSize + transfer.file!.rsrcSize
            transfer.actualTransferred      += Int64(oobdata.count)
            speedBytes                      += oobdata.count
            
            let percent                     = Double(transfer.actualTransferred) / Double(totalTransferSize) * 100.0
            transfer.percent                = percent
            time                            = TransfersTimeInterval()
            
            if transfer.speed == 0.0 || time - speedTime > 0.33 {
                transfer.speedCalculator.add(bytes: speedBytes, time: (time - speedTime))
                transfer.speed = transfer.speedCalculator.speed()
                
                speedBytes = 0
                speedTime = time
            }
            
            if transfer.dataTransferred + transfer.rsrcTransferred >= transfer.file!.dataSize + transfer.file!.rsrcSize {
                transfer.state = .disconnecting
                                
                // move to final path
                do {
                    print("atPath \(dataPath)")
                    print("toPath \(TransferWorker.defaultDownloadDestination(forPath: transfer.remotePath!))")
                    try FileManager.default.moveItem(atPath: dataPath, toPath: TransferWorker.defaultDownloadDestination(forPath: transfer.remotePath!))
                } catch let e {
                    print("rename failed \(e)")
                    DispatchQueue.main.async {
//                        let downloaderror = NSLocalizedString("Download Error", comment: "")
//                        let transferrenamefailed = NSLocalizedString("Transfer rename failed", comment: "")
//                        error = WiredError(withTitle: downloaderror, message: transferrenamefailed + " \(e)")
//
//                        Logger.error(error!)
                    }
                    
                    break
                }
                
                break
            }
        }
        
        transfer.speedCalculator.add(bytes: speedBytes, time: (time - speedTime))
        transfer.speed = transfer.speedCalculator.speed()
    }
    
    private func runUpload(_ transfer : Transfer) async throws {
        var error:WiredError? = nil
        var dataOffset:UInt64? = 0
        var dataLength:UInt64? = 0
        var sendBytes:UInt64 = 0
        var data = true
        var time:Double = 0.0, speedTime:Double = 0.0
        var speedBytes:Int = 0
                
        if transfer.transferConnection == nil {
            transfer.transferConnection = self.transfertConnectionForTransfer(transfer)
        }
                
        speedTime = TransfersTimeInterval()
        
        guard let connection = transfer.transferConnection else {
            print("No transfer connection")
            return
        }
        
        guard let url = transfer.connection?.url else {
            print("No connection URL")
            return
        }
        
        transfer.transferConnection?.interactive = false
        
        // connect transfer connection
        try connection.connect(withUrl: url, cipher: cipher, compression: compression, checksum: checksum)
        
        
        // send upload message
        if !connection.send(message: uploadFileMessage(for: transfer)) {
            print("Cannot upload file")
        }
        
        guard let message = self.run(transfer.transferConnection!, forTransfer: transfer, untilReceivingMessageName: "wired.transfer.upload_ready") else {
            print("Terminating tranfer")
            
            if transfer.isTerminating() == false {
                transfer.state = .disconnecting
            }
            
            self.finish(transfer)
            
            return
        }
        
        dataOffset = message.uint64(forField: "wired.transfer.data_offset")
        dataLength = transfer.file!.uploadDataSize - dataOffset!

        
        print("OK here")
        
        if transfer.file!.dataTransferred == 0 {
            transfer.file!.dataTransferred = dataOffset!
            transfer.dataTransferred = transfer.dataTransferred + Int64(dataOffset!)
        } else {
            transfer.file!.dataTransferred = dataOffset!
            transfer.dataTransferred = Int64(dataOffset!)
        }
        
        // send upload message
        if !connection.send(message: uploadMessage(for: transfer, dataLength: dataLength!, rsrcLength: 0)) {
            print("Cannot send upload message")
        }
        
        // transfer.speedCalculator.add(bytes: 0, time: 0)
        let fileURL = URL(fileURLWithPath: transfer.localPath!)
        
        transfer.speedCalculator.add(bytes: 0, time: 0)
        
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
                
        while transfer.isTerminating() == false {
            if data && dataLength == 0 {
                data = false
            }

            if data == false {
                break
            }

            fileHandle.seek(toFileOffset: dataOffset!)
            let readData = fileHandle.readData(ofLength: 8192)
            let readBytes = readData.count

            if readBytes <= 0 {
                if transfer.isTerminating() == false {
                    transfer.state = .disconnecting
                }

                let uploaderror = NSLocalizedString("Upload Error", comment: "")
                let cannotreadlocaldata = NSLocalizedString("Cannot read local data", comment: "")
                error = WiredError(withTitle: uploaderror, message: cannotreadlocaldata)

                Logger.error(error!)

                self.finish(transfer)

                break
            }

            sendBytes = (dataLength! < UInt64(readBytes)) ? dataLength! : UInt64(readBytes)
            dataOffset! += sendBytes
            
            do {
                try transfer.transferConnection!.socket.writeOOB(data: readData, timeout: 30.0)
            } catch {
                if transfer.isTerminating() == false {
                    transfer.state = .disconnecting
                }

                print("Error while writeOOB \(error)")
                
                break
            }

            dataLength!                 -= sendBytes
            transfer.dataTransferred    += Int64(sendBytes)
            transfer.actualTransferred  += Int64(readBytes)
            speedBytes                  += Int(readBytes)
            transfer.percent            = Double(transfer.dataTransferred) / Double(transfer.size) * 100
            time                        = TransfersTimeInterval()
            
            // speed calculation
            if transfer.speed == 0.0 || time - speedTime > 0.33 {
                transfer.speedCalculator.add(bytes: speedBytes, time: (time - speedTime))
                transfer.speed = transfer.speedCalculator.speed()
                
                speedBytes = 0
                speedTime = time
            }
        }

        fileHandle.closeFile()

        transfer.speedCalculator.add(bytes: speedBytes, time: (time - speedTime))
        transfer.speed = transfer.speedCalculator.speed()
        
        self.finish(transfer)
    }
    
    private func run(_ connection: TransferConnection, forTransfer transfer:Transfer, untilReceivingMessageName messageName:String) -> P7Message? {
        while transfer.isWorking() {
            // how to make large data transfert with Swift-NIO?
            guard let message = try? connection.readMessage() else {
                let localstring = NSLocalizedString("Transfer cannot read message, probably timed out", comment: "")
                print(localstring)
                return nil
            }

            if message.name == messageName {
                return message
            }

            if message.name == "wired.transfer.queue" {
                let position = message.uint32(forField: "wired.transfer.queue_position")
                
                //transfer.queu
                
            } else if message.name == "wired.transfer.send_ping" {
                let reply = P7Message(withName: "wired.ping", spec: spec)

                if let t = message.uint32(forField: "wired.transaction") {
                    reply.addParameter(field: "wired.transaction", value: t)
                }

                if transfer.transferConnection?.send(message: message) == false {
                    let localstring = NSLocalizedString("Transfer cannot reply ping", comment: "")
                    print(localstring)
                    return nil
                }

            } else if message.name == "wired.error" {
                let localstring = NSLocalizedString("Transfer error", comment: "")
                print(localstring)
                if let error = connection.spec.error(forMessage: message) {
                    let localstring = NSLocalizedString("Transfer error", comment: "")
                    print(localstring + ": \(error.name!)")
                }
                return nil
            }
        }
        return nil
    }
    
    private func finish(_ transfer: Transfer) {
        if transfer.state == .pausing || transfer.state == .paused {
            transfer.transferConnection?.disconnect()
            transfer.state = .paused
            
        }
        else if transfer.state == .stopping || transfer.state == .stopped {
            transfer.transferConnection?.disconnect()
            transfer.state = .stopped
            
        } else {
            transfer.transferConnection?.disconnect()
            transfer.state = .finished
        }
    }
    
    private func downloadFileMessage(for transfer:Transfer) -> P7Message {
        let message = P7Message(withName: "wired.transfer.download_file", spec: spec)
        message.addParameter(field: "wired.file.path", value: transfer.remotePath)
        message.addParameter(field: "wired.transfer.data_offset", value: UInt64(transfer.dataTransferred))
        message.addParameter(field: "wired.transfer.rsrc_offset", value: UInt64(transfer.rsrcTransferred))
        return message
    }
    
    private func uploadFileMessage(for transfer:Transfer) -> P7Message {
        let message = P7Message(withName: "wired.transfer.upload_file", spec: self.spec)
        message.addParameter(field: "wired.file.path", value: transfer.file?.path)
        message.addParameter(field: "wired.transfer.data_size", value: UInt64(transfer.size))
        message.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))
        return message
    }
    
    private func uploadMessage(for transfer:Transfer, dataLength:UInt64, rsrcLength:UInt64) -> P7Message {
        let data = FileManager.default.finderInfo(atPath: transfer.file!.path)!
        
        let message = P7Message(withName: "wired.transfer.upload", spec: self.spec)
        message.addParameter(field: "wired.file.path", value: transfer.file?.path)
        message.addParameter(field: "wired.transfer.data", value: dataLength)
        message.addParameter(field: "wired.transfer.rsrc", value: UInt64(0))
        message.addParameter(field: "wired.transfer.finderinfo", value: data.base64EncodedData())
        
        return message
    }
    
    private func transfertConnectionForTransfer(_ transfer: Transfer) -> TransferConnection {
        let connection = TransferConnection(withSpec: spec, transfer: transfer)
        
        connection.nick   = transfer.connection!.nick
        connection.status = transfer.connection!.status
        connection.icon   = transfer.connection!.icon
        
        return connection
    }
    
    public static func temporaryDownloadDestination(forPath path:String) -> String {
        @AppStorage("DownloadPath") var downloadPath: String = NSHomeDirectory().stringByAppendingPathComponent(path: "Downloads")
        
        let fileName = (path as NSString).lastPathComponent
        return downloadPath.stringByAppendingPathComponent(path: fileName).appendingFormat(".%@", Wired.transfersFileExtension)
    }
    
    
    public static func defaultDownloadDestination(forPath path:String) -> String {
        @AppStorage("DownloadPath") var downloadPath: String = NSHomeDirectory().stringByAppendingPathComponent(path: "Downloads")
        
        let fileName = (path as NSString).lastPathComponent
        return downloadPath.stringByAppendingPathComponent(path: fileName)
    }
}
