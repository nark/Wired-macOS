//
//  NewThreadView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct NewThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let board: Board

    @State private var subject: String = ""
    @State private var text: String    = ""
    @State private var isPosting       = false

    private var canPost: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Thread in \(board.name)")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 10) {
                TextField("Subject", text: $subject)

                Text("Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MarkdownComposer(text: $text, minHeight: 180, autoFocus: true, onOptionEnter: post)
            }
            .padding()

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Post") { post() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPost || isPosting)
            }
            .padding()
        }
        .frame(width: 560, height: 400)
    }

    private func post() {
        guard canPost, !isPosting else { return }
        isPosting = true
        Task {
            try? await runtime.addThread(toBoard: board,
                                         subject: subject.trimmingCharacters(in: .whitespaces),
                                         text: text.trimmingCharacters(in: .whitespaces))
            await MainActor.run { dismiss() }
        }
    }
}
