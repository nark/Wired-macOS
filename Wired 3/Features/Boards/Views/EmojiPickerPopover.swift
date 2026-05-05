//
//  EmojiPickerPopover.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/04/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

public struct EmojiPickerPopover: View {
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var hasLoadedLibrary = false

    private static let quickEmojis = ["👍", "👎", "❤️", "😂", "😮", "🎉", "🤔", "🔥", "👀", "✅"]
    private static let columns     = Array(repeating: GridItem(.flexible(), spacing: 1), count: 8)
    private static let searchableEmojis = EmojiLibrary.categories
        .flatMap(\.emojis)
        .map { emoji in (emoji: emoji, terms: emoji.emojiSearchTerms) }

    /// Flat filtered list used while a search query is active.
    private var searchResults: [String] {
        let q = searchText.lowercased()
        guard !q.isEmpty else { return [] }
        return Self.searchableEmojis
            .filter { $0.terms.contains(q) }
            .map(\.emoji)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search emoji…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if searchText.isEmpty {
                // ── Quick-access row ──────────────────────────────────
                HStack(spacing: 1) {
                    ForEach(Self.quickEmojis, id: \.self) { emoji in
                        emojiCell(emoji)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)

                Divider()

                if hasLoadedLibrary {
                    // ── Full library, sectioned ───────────────────────────
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Self.columns, spacing: 1) {
                            ForEach(EmojiLibrary.categories) { section in
                                Section {
                                    ForEach(section.emojis, id: \.self) { emoji in
                                        emojiCell(emoji)
                                    }
                                } header: {
                                    Text(section.name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 6)
                                        .padding(.top, 8)
                                        .padding(.bottom, 3)
                                        .background(Color(nsColor: .windowBackgroundColor))
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                    }
                    .frame(height: 300)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .task {
                            try? await Task.sleep(for: .milliseconds(80))
                            hasLoadedLibrary = true
                        }
                }
            } else {
                // ── Search results ────────────────────────────────────
                ScrollView(.vertical) {
                    if searchResults.isEmpty {
                        Text("No results for \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: Self.columns, spacing: 1) {
                            ForEach(searchResults, id: \.self) { emoji in
                                emojiCell(emoji)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                    }
                }
                .frame(height: 300)
            }
        }
        .frame(width: 296)
    }

    @ViewBuilder
    private func emojiCell(_ emoji: String) -> some View {
        Button {
            onSelect(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 20))
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.001)) // hit-test surface
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pointer Cursor

private struct PointerOnHoverModifier: ViewModifier {
    @State private var isHovering = false
    var externalIsHovering: Binding<Bool>?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { hovering in
            if hovering {
                if !(externalIsHovering?.wrappedValue ?? isHovering) {
                    externalIsHovering?.wrappedValue = true
                    isHovering = true
                    NSCursor.pointingHand.push()
                }
            } else {
                if externalIsHovering?.wrappedValue ?? isHovering {
                    externalIsHovering?.wrappedValue = false
                    isHovering = false
                    NSCursor.pop()
                }
            }
        }
        #else
        content
        #endif
    }
}

public extension View {
    func pointerOnHover(isHovering: Binding<Bool>? = nil) -> some View {
        modifier(PointerOnHoverModifier(externalIsHovering: isHovering))
    }
}
