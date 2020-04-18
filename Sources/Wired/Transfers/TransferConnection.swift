//
//  TransferConnection.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

public class TransferConnection: ServerConnection {
    public var transfer: Transfer!
    
    public init(withSpec spec: P7Spec, transfer: Transfer) {
        super.init(withSpec: spec)
        
        self.transfer = transfer
    }
}
