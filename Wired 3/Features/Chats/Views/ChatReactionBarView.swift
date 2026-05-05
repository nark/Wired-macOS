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

    private var canReact: Bool {
        runtime.canUseChatReactions && event.serverMessageID != nil
    }

    var body: some View {
        if canReact, !event.reactions.isEmpty {
            HStack(spacing: 6) {
                ForEach(event.reactions) { reaction in
                    ChatReactionChipView(
                        reaction: reaction,
                        allReactions: event.reactions,
                        isNew: event.newReactionEmojis.contains(reaction.emoji),
                        onToggle: { emoji in toggle(emoji) }
                    )
                }
            }
            .animation(.easeInOut(duration: 0.15), value: event.reactions.map(\.count))
            .task(id: event.serverMessageID ?? "") {
                guard !event.reactionsLoaded, event.serverMessageID != nil else { return }
                try? await runtime.getChatReactions(for: event)
            }
        }
    }

    private func toggle(_ emoji: String) {
        Task { try? await runtime.toggleChatReaction(emoji: emoji, on: event) }
    }
}

/// Long-press handler that opens the chat reaction picker. Use on any
/// bubble (text, image, file) — long-press never collides with the
/// existing single/double-tap actions on image bubbles. The popover and
/// the toggle action are owned by the modifier so the gesture surface
/// stays self-contained.
struct ChatReactionLongPressModifier: ViewModifier {
    @Environment(ConnectionRuntime.self) private var runtime
    let event: ChatEvent
    /// When true, double-click also opens the picker (text bubbles only —
    /// image bubbles use double-click to open QuickLook).
    let allowDoubleClick: Bool

    @State private var showPicker = false
    @State private var isSelectionPending = false

    private var canReact: Bool {
        runtime.canUseChatReactions && event.serverMessageID != nil
    }

    func body(content: Content) -> some View {
        if canReact {
            let withLongPress = content
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) {
                    guard !isSelectionPending else { return }
                    showPicker = true
                }
                .popover(
                    isPresented: $showPicker,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    EmojiPickerPopover { emoji in
                        selectEmoji(emoji)
                    }
                }
            if allowDoubleClick {
                withLongPress.onTapGesture(count: 2) {
                    guard !isSelectionPending else { return }
                    showPicker = true
                }
            } else {
                withLongPress
            }
        } else {
            content
        }
    }

    private func selectEmoji(_ emoji: String) {
        guard !isSelectionPending else { return }
        isSelectionPending = true
        showPicker = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            try? await runtime.toggleChatReaction(emoji: emoji, on: event)
            isSelectionPending = false
        }
    }
}

extension View {
    /// Reaction picker on long-press (every bubble) and optionally on
    /// double-click (text bubbles, where double-click is otherwise unused).
    func chatReactionGesture(for event: ChatEvent, allowDoubleClick: Bool = false) -> some View {
        modifier(ChatReactionLongPressModifier(event: event, allowDoubleClick: allowDoubleClick))
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
                Capsule().fill(chipBackgroundColor)
            )
            .overlay(
                Capsule().strokeBorder(
                    reaction.isOwn ? Color.accentColor : Color(nsColor: .separatorColor),
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

    private var chipBackgroundColor: Color {
        reaction.isOwn ? Color.accentColor : Color(nsColor: .controlBackgroundColor)
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
