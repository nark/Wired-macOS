//
//  ReplyView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
#if os(macOS)
import AppKit
private typealias ReplyPlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
private typealias ReplyPlatformImage = UIImage
#endif

struct ReplyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let thread: BoardThread
    let initialText: String?

    @State private var text: String  = ""
    @State private var isPosting     = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var threadAuthorIcon: ReplyPlatformImage? {
        guard let iconData = thread.posts.first?.icon else { return nil }
        return ReplyPlatformImage(data: iconData)
    }

    private var threadCreatedDateText: String {
        Self.dateFormatter.string(from: thread.postDate)
    }

    private var lastReplyDateText: String {
        Self.dateFormatter.string(from: thread.lastReplyDate ?? thread.postDate)
    }

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private func authorIconView(_ icon: ReplyPlatformImage) -> some View {
        #if os(macOS)
        Image(nsImage: icon)
            .resizable()
        #else
        Image(uiImage: icon)
            .resizable()
        #endif
    }

    init(thread: BoardThread, initialText: String? = nil) {
        self.thread = thread
        self.initialText = initialText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Re: \(thread.subject)")
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let icon = threadAuthorIcon {
                        authorIconView(icon)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 26, height: 26)
                            .foregroundStyle(.secondary)
                    }

                    Text(thread.nick)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 14) {
                    Label("Thread: \(threadCreatedDateText)", systemImage: "calendar")
                    Label("Derniere reponse: \(lastReplyDateText)", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            // Editor
            MarkdownComposer(text: $text, minHeight: 180, autoFocus: true, onOptionEnter: reply)
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
        .frame(width: 600, height: 460)
        .onAppear {
            if text.isEmpty, let initialText, !initialText.isEmpty {
                text = initialText
            }
        }
    }

    private func reply() {
        guard canPost, !isPosting else { return }
        isPosting = true
        Task {
            try? await runtime.addPost(toThread: thread,
                                       text: text.trimmingCharacters(in: .whitespaces))
            await MainActor.run { dismiss() }
        }
    }
}
