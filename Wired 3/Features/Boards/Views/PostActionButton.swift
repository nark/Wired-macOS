//
//  PostActionButton.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/04/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct PostActionButton: View {
    let label: String
    let icon: String
    var destructive: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(destructive
                                 ? (isHovering ? Color.red : Color.red.opacity(0.75))
                                 : (isHovering ? Color.primary : Color.secondary))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering
                              ? (destructive ? Color.red.opacity(0.08) : Color.secondary.opacity(0.1))
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isHovering
                            ? (destructive ? Color.red.opacity(0.35) : Color.secondary.opacity(0.4))
                            : Color.secondary.opacity(0.2),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
