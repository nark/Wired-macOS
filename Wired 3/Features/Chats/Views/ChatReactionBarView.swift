//
//  ChatReactionBarView.swift
//  Wired-macOS
//
//  Wired 3.2 chat-message reaction surface. Mirrors the board reactions
//  bar (ReactionBarView / ReactionChipView) but operates on ChatEvent
//  and the new wired.chat.reaction.* messages. Hidden entirely when the
//  peer doesn't advertise wired.chat.add_reaction so 3.1 servers degrade
//  cleanly.
//

import SwiftUI

struct ChatReactionBarView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    let event: ChatEvent
    /// Hover state from the parent message row. The "+" picker is hidden
    /// until the user hovers, to avoid cluttering the chat with always-on
    /// affordances.
    var isParentHovered: Bool = false

    @State private var showEmojiPicker = false

    private var canReact: Bool {
        runtime.canUseChatReactions && event.serverMessageID != nil
    }

    var body: some View {
        if canReact, !event.reactions.isEmpty || isParentHovered {
            HStack(spacing: 6) {
                ForEach(event.reactions) { reaction in
                    ChatReactionChipView(
                        reaction: reaction,
                        allReactions: event.reactions,
                        isNew: event.newReactionEmojis.contains(reaction.emoji),
                        onToggle: { emoji in toggle(emoji) }
                    )
                }
                addButton
            }
            .animation(.easeInOut(duration: 0.15), value: event.reactions.map(\.count))
            .task(id: event.serverMessageID ?? "") {
                guard !event.reactionsLoaded, event.serverMessageID != nil else { return }
                try? await runtime.getChatReactions(for: event)
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button { showEmojiPicker = true } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Add a reaction")
        .popover(isPresented: $showEmojiPicker, arrowEdge: .bottom) {
            EmojiPickerPopover { emoji in
                showEmojiPicker = false
                toggle(emoji)
            }
        }
    }

    private func toggle(_ emoji: String) {
        Task { try? await runtime.toggleChatReaction(emoji: emoji, on: event) }
    }
}

private struct ChatReactionChipView: View {
    let reaction: ChatReactionSummary
    let allReactions: [ChatReactionSummary]
    var isNew: Bool = false
    let onToggle: (String) -> Void

    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var shake: CGFloat = 0

    var body: some View {
        Button { onToggle(reaction.emoji) } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji).font(.system(size: 13))
                Text("\(reaction.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reaction.isOwn ? .white : .primary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(reaction.isOwn ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(
                    reaction.isOwn ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .offset(x: shake)
        .onChange(of: isNew) { _, v in if v { performShake() } }
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    showPopover = true
                }
            } else {
                showPopover = false
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ChatReactionSummaryPopover(reactions: allReactions)
        }
        .contextMenu {
            Button(reaction.isOwn ? "Remove your reaction" : "React with \(reaction.emoji)") {
                onToggle(reaction.emoji)
            }
        }
    }

    private func performShake() {
        let step = 0.07
        withAnimation(.easeInOut(duration: step)) { shake = -4 }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 1) {
            withAnimation(.easeInOut(duration: step)) { shake =  4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 2) {
            withAnimation(.easeInOut(duration: step)) { shake = -3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 3) {
            withAnimation(.easeInOut(duration: step)) { shake =  2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 4) {
            withAnimation(.easeInOut(duration: step)) { shake =  0 }
        }
    }
}

private struct ChatReactionSummaryPopover: View {
    let reactions: [ChatReactionSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reactions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(reactions) { reaction in
                        HStack(alignment: .top, spacing: 10) {
                            Text(reaction.emoji).font(.title3).frame(width: 28, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("\(reaction.count) reaction\(reaction.count == 1 ? "" : "s")")
                                        .font(.subheadline.weight(.medium))
                                    if reaction.isOwn {
                                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                                    }
                                }
                                if !reaction.nicks.isEmpty {
                                    Text(reaction.nicks.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        if reaction.id != reactions.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 230)
        .padding(.bottom, 6)
    }
}
