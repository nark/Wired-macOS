//
//  NSTableView+Extension.swift
//  Wired
//
//  Created by Rafael Warnault on 12/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Foundation


extension NSTableView {
    public func scrollToBottom() {
        self.perform(#selector(scrollToLastRow), with: nil, afterDelay: 0.1)
    }
    
    @objc private func scrollToLastRow() {
        self.scrollToVisible(self.rect(ofRow: self.numberOfRows - 1))
    }
}
