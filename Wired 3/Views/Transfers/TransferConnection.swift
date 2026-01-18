//
//  TransferConnection.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 12/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

@inline(__always) func TransfersTimeInterval() -> Double {
    var tv = timeval()
    
    gettimeofday(&tv, nil)
    
    return Double(tv.tv_sec) + Double(tv.tv_usec) / Double(USEC_PER_SEC)
}


public class TransferConnection: AsyncConnection {
    public var transfer: Transfer
    
    public init(withSpec spec: P7Spec, transfer: Transfer) {
        self.transfer = transfer
        
        super.init(withSpec: spec)
    }
}

