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
            Form {
                TextField("Subject", text: $subject)

                Text("Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            .formStyle(.grouped)

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
        .frame(width: 520, height: 360)
    }

    private func post() {
        isPosting = true
        Task {
            try? await runtime.addThread(toBoard: board,
                                         subject: subject.trimmingCharacters(in: .whitespaces),
                                         text: text.trimmingCharacters(in: .whitespaces))
            await MainActor.run { dismiss() }
        }
    }
}
