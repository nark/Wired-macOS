//
//  ToolbarContent.swift
//  Leeza
//
//  Created by Codex on 02/03/2026.
//

import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func sharedBackgroundHiddenIfAvailable() -> some ToolbarContent {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
