//
//  ConnectionRuntime+ChatReactions.swift
//  Wired-macOS
//
//  Wired 3.2 chat-reactions runtime helpers, factored out of
//  ConnectionRuntime to keep that type's body length under SwiftLint
//  thresholds.
//

import Foundation
import WiredSwift

extension ConnectionRuntime {

    /// Whether the connected peer advertises the 3.2 chat-reactions surface.
    var canUseChatReactions: Bool {
        connection?.socket.peerKnows(messageNamed: "wired.chat.add_reaction") ?? false
    }

    private func chatEvent(chatID: UInt32, messageID: String) -> ChatEvent? {
        guard let chat = chat(withID: chatID) else { return nil }
        return chat.messages.first { $0.serverMessageID == messageID && $0.type != .event }
    }

    /// Lazy fetch of reaction summaries for a chat message. Safe to call
    /// repeatedly: results overwrite `event.reactions` and flag
    /// `reactionsLoaded`.
    func getChatReactions(for event: ChatEvent) async throws {
        guard let messageID = event.serverMessageID else { return }
        guard let connection = connection as? AsyncConnection else {
            throw AsyncConnectionError.notConnected
        }

        let m = P7Message(withName: "wired.chat.get_reactions", spec: spec)
        m.addParameter(field: "wired.chat.id", value: event.chat.id)
        m.addParameter(field: "wired.chat.message.id", value: messageID)

        var summaries: [ChatReactionSummary] = []
        for try await response in try connection.sendAndWaitMany(m) {
            guard response.name == "wired.chat.reaction_list",
                  let emoji = response.string(forField: "wired.chat.reaction.emoji"),
                  let count = response.uint32(forField: "wired.chat.reaction.count"),
                  let isOwn = response.bool(forField: "wired.chat.reaction.is_own")
            else { continue }
            let nicksStr = response.string(forField: "wired.chat.reaction.nicks") ?? ""
            let nicks = nicksStr.isEmpty ? [] : nicksStr.components(separatedBy: "|")
            summaries.append(ChatReactionSummary(emoji: emoji, count: Int(count), isOwn: isOwn, nicks: nicks))
        }
        event.reactions = summaries
        event.reactionsLoaded = true
    }

    /// Toggle a reaction. If the user already owns this emoji on the
    /// message, sends `remove_reaction`; otherwise `add_reaction`. The
    /// authoritative state arrives via the `reaction_added` /
    /// `reaction_removed` broadcast.
    func toggleChatReaction(emoji: String, on event: ChatEvent) async throws {
        guard let messageID = event.serverMessageID else { return }
        let isRemoval = event.reactions.first(where: { $0.emoji == emoji })?.isOwn == true
        let messageName = isRemoval ? "wired.chat.remove_reaction" : "wired.chat.add_reaction"

        let m = P7Message(withName: messageName, spec: spec)
        m.addParameter(field: "wired.chat.id", value: event.chat.id)
        m.addParameter(field: "wired.chat.message.id", value: messageID)
        m.addParameter(field: "wired.chat.reaction.emoji", value: emoji)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
        // Refresh so isOwn is accurate even when our broadcast races our reply.
        try? await getChatReactions(for: event)
    }

    /// Apply an incoming `wired.chat.reaction_added` / `reaction_removed`
    /// to the in-memory event. Mirrors `applyReactionBroadcast` for boards.
    @discardableResult
    func applyChatReactionBroadcast(chatID: UInt32, messageID: String,
                                    emoji: String, count: Int, added: Bool,
                                    nick: String?, countAsUnread: Bool) -> ChatEvent? {
        guard let chat = chat(withID: chatID) else { return nil }
        let event = chatEvent(chatID: chatID, messageID: messageID)

        let isOwnReaction = nick == nil || nick == currentNick

        if added, !isOwnReaction, countAsUnread {
            chat.unreadReactionCount += 1
            connectionController.updateNotificationsBadge()
        }
        if !added, !isOwnReaction, chat.unreadReactionCount > 0 {
            chat.unreadReactionCount -= 1
            connectionController.updateNotificationsBadge()
        }

        guard let event else { return nil }

        if count == 0 {
            event.reactions.removeAll { $0.emoji == emoji }
        } else if let idx = event.reactions.firstIndex(where: { $0.emoji == emoji }) {
            var nicks = event.reactions[idx].nicks
            if added, let n = nick, !nicks.contains(n) { nicks.append(n) }
            event.reactions[idx] = ChatReactionSummary(
                emoji: emoji,
                count: count,
                isOwn: event.reactions[idx].isOwn,
                nicks: nicks
            )
        } else if added {
            event.reactions.append(ChatReactionSummary(
                emoji: emoji, count: count,
                isOwn: isOwnReaction && nick == currentNick,
                nicks: nick.map { [$0] } ?? []
            ))
        }
        event.reactionsLoaded = true

        if added, !isOwnReaction {
            event.newReactionEmojis.insert(emoji)
            let captured = event
            let capturedEmoji = emoji
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                captured.newReactionEmojis.remove(capturedEmoji)
            }
        }

        return event
    }
}
