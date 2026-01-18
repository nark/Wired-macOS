//
//  String.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 03/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

extension String {
    func replacingEmoticons(using map: [String: String]) -> String {
        var result = self
        for (key, value) in map {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }
}

