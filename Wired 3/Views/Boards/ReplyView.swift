//
//  ReplyView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct ReplyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let thread: BoardThread

    @State private var text: String  = ""
    @State private var isPosting     = false

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Re: \(thread.subject)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding()

            Divider()

            // Editor
            TextEditor(text: $text)
                .font(.body)
                .padding(8)

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Reply") { reply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPost || isPosting)
            }
            .padding()
        }
        .frame(width: 480, height: 280)
    }

    private func reply() {
        isPosting = true
        Task {
            try? await runtime.addPost(toThread: thread,
                                       text: text.trimmingCharacters(in: .whitespaces))
            await MainActor.run { dismiss() }
        }
    }
}
