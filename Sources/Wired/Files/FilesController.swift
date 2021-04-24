//
//  FilesController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

public class FilesController: ConnectionObject {
    var rootFile:File!
    
    public override init(_ connection: ServerConnection) {
        super.init(connection)
        
        self.rootFile = File("/", connection: connection)
    }
    
    public convenience init(withRoot root: String, connection: ServerConnection) {
        self.init(connection)
                
        self.rootFile = File(root, connection: connection)
    }
    
    public func load(ofFile file:File?, reload:Bool = false) {
        if let f = file {
            f.load(reload: reload)
        } else {
            rootFile.load(reload: reload)
        }
    }
    
    
    public func delete(file:File) {
        let message = P7Message(withName: "wired.file.delete", spec: self.connection.spec)
        
        message.addParameter(field: "wired.file.path", value: file.path)
        
        if let blockConnection = self.connection {
            blockConnection.send(message: message, completionBlock: { (response) in
                if response!.name == "wired.okay" {
                    NotificationCenter.default.post(name: .didDeleteFile, object: file)
                }
            })
        }
    }
    
    
    public func file(atPath path: String) -> File? {
//        let message = P7Message(withName: "wired.file.get_info", spec: self.connection.spec)
//        message.addParameter(field: "wired.file.path", value: path)
//        
//        if self.connection.send(message: message) == true {
//            if let response = self.connection.readMessage() {
//                return File(response, connection: self.connection)
//            }
//        }
        
        return nil
    }
}
