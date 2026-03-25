//
//  ChatMessagesView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ChatMessagesView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @AppStorage("TimestampInChat") private var timestampInChat: Bool = false
    @AppStorage("TimestampEveryMin") private var timestampEveryMin: Int = 5
    @State private var animatedNewMessageID: UUID?
    @State private var revealNewMessage = true
    @State private var liveSlotTypingUserID: UInt32?
    @State private var isLiveSlotTypingVisible = false
    @State private var liveSlotMessageID: UUID?
    @State private var liveSlotMorphProgress: CGFloat = 0
    @State private var liveSlotClearTask: Task<Void, Never>?
    @State private var scrollToBottomTask: Task<Void, Never>?
    @State private var pendingLiveSlotTimestampDate: Date?
    
    var chat: Chat
    var searchText: String = ""
    var topOverlayInset: CGFloat = 0
    var bottomOverlayInset: CGFloat = 0
    var keyboardShowTrigger: Int = 0
    var onUserInteraction: (() -> Void)? = nil

    private let bottomAnchorID = "chat-messages-bottom-anchor"
    private let scrollIndicatorBottomInset: CGFloat = 8

    private var effectiveTimestampInterval: TimeInterval {
        TimeInterval(max(timestampEveryMin, 1) * 60)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    private var filteredMessages: [ChatEvent] {
        chat.filteredMessages(matching: normalizedSearchText)
    }

    private var visibleMessageIDs: Set<UUID> {
        Set(filteredMessages.map(\.id))
    }

    private var displayItems: [ChatDisplayItem] {
        guard timestampInChat else {
            var items = transcriptMessages.map(ChatDisplayItem.message)
            if let liveSlotPresentation {
                items.append(.liveSlot(liveSlotPresentation))
            }
            return items
        }

        var items: [ChatDisplayItem] = []
        var lastInsertedTimestampDate: Date?
        var didInsertPendingLiveSlotTimestamp = false

        for message in transcriptMessages {
            if let pendingLiveSlotTimestampDate,
               !didInsertPendingLiveSlotTimestamp,
               pendingLiveSlotTimestampDate <= message.date,
               shouldInsertTimestamp(
                    at: pendingLiveSlotTimestampDate,
                    lastTimestampDate: lastInsertedTimestampDate
               ) {
                items.append(.timestamp(id: "live-slot-timestamp", date: pendingLiveSlotTimestampDate))
                lastInsertedTimestampDate = pendingLiveSlotTimestampDate
                didInsertPendingLiveSlotTimestamp = true
            }

            if shouldInsertTimestamp(before: message, lastTimestampDate: lastInsertedTimestampDate) {
                items.append(.timestamp(id: "timestamp-\(message.id.uuidString)", date: message.date))
                lastInsertedTimestampDate = message.date
            }

            items.append(.message(message))
        }

        if let pendingLiveSlotTimestampDate,
           !didInsertPendingLiveSlotTimestamp,
           shouldInsertTimestamp(
                at: pendingLiveSlotTimestampDate,
                lastTimestampDate: lastInsertedTimestampDate
           ) {
            items.append(.timestamp(id: "live-slot-timestamp", date: pendingLiveSlotTimestampDate))
            lastInsertedTimestampDate = pendingLiveSlotTimestampDate
        }

        if let liveSlotPresentation {
            items.append(.liveSlot(liveSlotPresentation))
        }

        return items
    }

    private var transcriptMessages: [ChatEvent] {
        guard let liveSlotMessageID else { return filteredMessages }
        return filteredMessages.filter { $0.id != liveSlotMessageID }
    }

    private var currentTypingUserID: UInt32? {
        guard !isSearching else { return nil }
        return chat.primaryTypingUser?.id
    }

    private var liveSlotPresentation: LiveSlotPresentation? {
        if let liveSlotMessageID,
           let liveMessage = filteredMessages.first(where: { $0.id == liveSlotMessageID }) {
            return .message(
                liveMessage,
                morphProgress: liveSlotMorphProgress
            )
        }

        if let liveSlotTypingUserID {
            return .typing(
                userID: liveSlotTypingUserID,
                isVisible: isLiveSlotTypingVisible
            )
        }

        return nil
    }
    
    var body: some View {
        if isSearching && filteredMessages.isEmpty {
            ContentUnavailableView(
                "No Matching Messages",
                systemImage: "magnifyingglass",
                description: Text("No message in \"\(chat.name)\" matches \"\(normalizedSearchText)\".")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            messagesList
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if topOverlayInset > 0 {
                        Color.clear
                            .frame(height: topOverlayInset)
                    }

                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .timestamp(_, let date):
                            ChatInlineTimestampView(date: date)
                        case .message(let message):
                            messageView(for: message, index: index)
                        case .liveSlot(let presentation):
                            liveSlotView(for: presentation, index: index)
                        }
                    }

                    Color.clear
                        .frame(height: max(bottomOverlayInset + scrollIndicatorBottomInset, 0.1))
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 10)
            }
#if os(macOS)
            .background(
                ChatListInteractionObserver {
                    onUserInteraction?()
                }
            )
#endif
            .background(.clear)
            .textSelection(.enabled)
            .frame(maxHeight: .infinity)
            .onChange(of: chat.messages.last?.id) {
                if let lastMessage = chat.messages.last,
                   visibleMessageIDs.contains(lastMessage.id) {
                    let lastID = lastMessage.id
                    let bridgeTyping =
                        liveSlotTypingUserID == lastMessage.user.id
                        && lastMessage.type == .say

                    if bridgeTyping {
                        morphLiveSlotIntoMessage(lastMessage)
                        scheduleScrollToBottom(with: proxy, animated: false, delays: [0.0, 0.38])
                        animatedNewMessageID = nil
                        revealNewMessage = true
                    } else {
                        if liveSlotTypingUserID == lastMessage.user.id {
                            clearLiveSlotTyping()
                        }
                        liveSlotMessageID = nil
                        liveSlotMorphProgress = 0
                        scheduleScrollToBottom(with: proxy)
                        animatedNewMessageID = lastID
                        revealNewMessage = false

                        DispatchQueue.main.asyncAfter(deadline: .now()) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                revealNewMessage = true
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if animatedNewMessageID == lastID {
                                animatedNewMessageID = nil
                            }
                        }
                    }
                }
            }
            .onAppear {
                syncLiveSlotTyping(animated: false)
                scheduleScrollToBottom(with: proxy)
            }
            .onChange(of: keyboardShowTrigger) {
                scheduleScrollToBottom(with: proxy)
            }
            .onChange(of: timestampInChat) {
                if !timestampInChat {
                    pendingLiveSlotTimestampDate = nil
                } else if currentTypingUserID != nil {
                    syncPendingLiveSlotTimestamp(referenceDate: .now)
                }
                scheduleScrollToBottom(with: proxy)
            }
            .onChange(of: timestampEveryMin) {
                scheduleScrollToBottom(with: proxy)
            }
            .onChange(of: normalizedSearchText) {
                syncLiveSlotTyping(animated: true)
                scheduleScrollToBottom(with: proxy)
            }
            .onChange(of: chat.typingIndicatorText) {
                let nextTypingUserID = currentTypingUserID
                let shouldScrollToTyping =
                    nextTypingUserID != nil &&
                    liveSlotMessageID == nil &&
                    (!isLiveSlotTypingVisible || liveSlotTypingUserID != nextTypingUserID)

                syncLiveSlotTyping(animated: true)

                if shouldScrollToTyping {
                    scheduleScrollToBottom(with: proxy, animated: true)
                }
            }
            .onChange(of: chat.activeTypingUserIDs) {
                let nextTypingUserID = currentTypingUserID
                let shouldScrollToTyping =
                    nextTypingUserID != nil &&
                    liveSlotMessageID == nil &&
                    (!isLiveSlotTypingVisible || liveSlotTypingUserID != nextTypingUserID)

                syncLiveSlotTyping(animated: true)

                if shouldScrollToTyping {
                    scheduleScrollToBottom(with: proxy, animated: true)
                }
            }
            .onChange(of: bottomOverlayInset) {
                scheduleScrollToBottom(with: proxy, animated: true)
            }
            .onDisappear {
                liveSlotClearTask?.cancel()
                scrollToBottomTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private func messageView(for message: ChatEvent, index: Int) -> some View {
        if message.type == .say {
            let previous = index > 0 ? displayItems[index - 1].chatMessage : nil
            let nextItem = index < (displayItems.count - 1) ? displayItems[index + 1] : nil
            let next = nextItem?.chatMessage
            let sameAsPrevious = previous?.type == .say && previous?.user.id == message.user.id
            let sameAsNext =
                (next?.type == .say && next?.user.id == message.user.id)
                || nextItem?.continuesGrouping(forUserID: message.user.id) == true

            ChatSayMessageView(
                message: message,
                showNickname: !sameAsPrevious,
                showAvatar: !sameAsNext,
                isGroupedWithNext: sameAsNext
            )
            .environment(runtime)
            .scaleEffect(message.id == animatedNewMessageID ? (revealNewMessage ? 1 : 0.94) : 1)
            .opacity(message.id == animatedNewMessageID ? (revealNewMessage ? 1 : 0) : 1)
        }
        else if message.type == .me {
            ChatMeMessageView(message: message)
                .environment(runtime)
                .scaleEffect(message.id == animatedNewMessageID ? (revealNewMessage ? 1 : 0.94) : 1)
                .opacity(message.id == animatedNewMessageID ? (revealNewMessage ? 1 : 0) : 1)
        }
        else if message.type == .join || message.type == .leave || message.type == .event {
            ChatEventView(message: message)
                .environment(runtime)
                .scaleEffect(message.id == animatedNewMessageID ? (revealNewMessage ? 1 : 0.94) : 1)
                .opacity(message.id == animatedNewMessageID ? (revealNewMessage ? 1 : 0) : 1)
        }
    }

    private func shouldInsertTimestamp(before message: ChatEvent, lastTimestampDate: Date?) -> Bool {
        shouldInsertTimestamp(at: message.date, lastTimestampDate: lastTimestampDate)
    }

    private func shouldInsertTimestamp(at date: Date, lastTimestampDate: Date?) -> Bool {
        guard let lastTimestampDate else { return true }
        return date.timeIntervalSince(lastTimestampDate) >= effectiveTimestampInterval
    }

    private var lastTranscriptTimestampDate: Date? {
        var lastTimestampDate: Date?

        for message in transcriptMessages {
            if shouldInsertTimestamp(before: message, lastTimestampDate: lastTimestampDate) {
                lastTimestampDate = message.date
            }
        }

        return lastTimestampDate
    }

    private func scheduleScrollToBottom(
        with proxy: ScrollViewProxy,
        animated: Bool = false,
        delays: [TimeInterval] = [0.0]
    ) {
        scrollToBottomTask?.cancel()
        scrollToBottomTask = Task { @MainActor in
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                }
                guard !Task.isCancelled else { return }
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    @MainActor
    private func syncLiveSlotTyping(animated: Bool) {
        let nextTypingUserID = currentTypingUserID

        if let nextTypingUserID, liveSlotMessageID == nil {
            liveSlotClearTask?.cancel()
            liveSlotTypingUserID = nextTypingUserID
            syncPendingLiveSlotTimestamp(referenceDate: .now)

            guard !isLiveSlotTypingVisible else { return }

            if animated {
                isLiveSlotTypingVisible = false
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                        isLiveSlotTypingVisible = true
                    }
                }
            } else {
                isLiveSlotTypingVisible = true
            }
            return
        }

        guard liveSlotMessageID == nil, liveSlotTypingUserID != nil else { return }

        liveSlotClearTask?.cancel()

        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                isLiveSlotTypingVisible = false
            }

            liveSlotClearTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if currentTypingUserID == nil && liveSlotMessageID == nil {
                        liveSlotTypingUserID = nil
                    }
                }
            }
        } else {
            isLiveSlotTypingVisible = false
            liveSlotTypingUserID = nil
        }
    }

    @MainActor
    private func clearLiveSlotTyping() {
        liveSlotClearTask?.cancel()
        isLiveSlotTypingVisible = false
        liveSlotTypingUserID = nil
    }

    @MainActor
    private func syncPendingLiveSlotTimestamp(referenceDate: Date) {
        guard timestampInChat else {
            pendingLiveSlotTimestampDate = nil
            return
        }

        let lastTimestampDate = pendingLiveSlotTimestampDate ?? lastTranscriptTimestampDate
        guard shouldInsertTimestamp(at: referenceDate, lastTimestampDate: lastTimestampDate) else {
            return
        }

        if pendingLiveSlotTimestampDate == nil {
            pendingLiveSlotTimestampDate = referenceDate
        }
    }

    @MainActor
    private func morphLiveSlotIntoMessage(_ message: ChatEvent) {
        liveSlotClearTask?.cancel()
        liveSlotTypingUserID = message.user.id
        liveSlotMessageID = message.id
        liveSlotMorphProgress = 0
        isLiveSlotTypingVisible = true

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.32)) {
                liveSlotMorphProgress = 1
            }
        }

        liveSlotClearTask = Task {
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard liveSlotMessageID == message.id else { return }

                liveSlotMessageID = nil
                liveSlotMorphProgress = 0
                liveSlotTypingUserID = nil
                isLiveSlotTypingVisible = false

                syncLiveSlotTyping(animated: false)
            }
        }
    }

    @ViewBuilder
    private func liveSlotView(for presentation: LiveSlotPresentation, index: Int) -> some View {
        let previous = index > 0 ? displayItems[index - 1].chatMessage : nil
        let isGroupedWithPrevious = previous?.type == .say && previous?.user.id == presentation.userID

        ChatIncomingLiveSlotView(
            presentation: presentation,
            user: chat.users.first(where: { $0.id == presentation.userID }),
            isGroupedWithPrevious: isGroupedWithPrevious
        )
    }

}

private enum ChatDisplayItem: Identifiable {
    case timestamp(id: String, date: Date)
    case message(ChatEvent)
    case liveSlot(LiveSlotPresentation)

    var id: String {
        switch self {
        case .timestamp(let id, _):
            return id
        case .message(let message):
            return "message-\(message.id.uuidString)"
        case .liveSlot:
            return "live-slot"
        }
    }

    var chatMessage: ChatEvent? {
        switch self {
        case .timestamp:
            return nil
        case .message(let message):
            return message
        case .liveSlot:
            return nil
        }
    }

    @MainActor
    func continuesGrouping(forUserID userID: UInt32) -> Bool {
        switch self {
        case .liveSlot(let presentation):
            switch presentation {
            case .typing(let typingUserID, _):
                return typingUserID == userID
            case .message(let message, _):
                return message.user.id == userID
            }
        case .message, .timestamp:
            return false
        }
    }
}

private enum LiveSlotPresentation {
    case typing(userID: UInt32, isVisible: Bool)
    case message(ChatEvent, morphProgress: CGFloat)

    @MainActor
    var userID: UInt32 {
        switch self {
        case .typing(let userID, _):
            return userID
        case .message(let message, _):
            return message.user.id
        }
    }
}

private struct ChatInlineTimestampView: View {
    let date: Date

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(.primary.opacity(0.06))
                )

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
}

private struct ChatIncomingLiveSlotView: View {
    let presentation: LiveSlotPresentation
    let user: User?
    let isGroupedWithPrevious: Bool

    private let nicknameReservedHeight: CGFloat = 16
    private let typingBubbleContentSize = CGSize(width: 31, height: 16)
    private let bubbleVerticalPadding: CGFloat = 8
    private let bubbleHorizontalPadding: CGFloat = 16
    private let bubbleLeadingInset: CGFloat = 8
    @State private var availableBubbleWidth: CGFloat = .zero
    @State private var isMessageTextVisible = false
    @State private var textRevealTask: Task<Void, Never>?

    private var handoffProgress: CGFloat {
        switch presentation {
        case .typing:
            return 0
        case .message(_, let morphProgress):
            return morphProgress
        }
    }

    private var typingFadeProgress: CGFloat {
        min(max(handoffProgress / 0.62, 0), 1)
    }

    private var messageRevealProgress: CGFloat {
        min(max((handoffProgress - 0.18) / 0.82, 0), 1)
    }

    private var nicknameOpacity: CGFloat {
        guard !isGroupedWithPrevious else { return 0 }
        return messageRevealProgress
    }

    private var nicknameText: String {
        user?.nick ?? " "
    }

    private var typingStatusText: String {
        "\(user?.nick ?? "User") is typing..."
    }

    private var messageText: AttributedString {
        switch presentation {
        case .typing:
            return "".attributedWithDetectedLinks(linkColor: .blue)
        case .message(let message, _):
            return message.text.attributedWithDetectedLinks(linkColor: .blue)
        }
    }

    private var messageString: String {
        switch presentation {
        case .typing:
            return ""
        case .message(let message, _):
            return message.text
        }
    }

    private var resolvedTypingContentSize: CGSize {
        typingBubbleContentSize
    }

    private var isImageOnlyMessage: Bool {
        guard case .message(let message, _) = presentation else { return false }
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = message.text.detectedHTTPImageURLs().first else { return false }
        return trimmed == url.absoluteString
    }

    private var resolvedMessageContentSize: CGSize {
        if case .message = presentation {
            if isImageOnlyMessage {
                // Target the image placeholder size (280×190) minus bubble padding
                return CGSize(
                    width: 280 - (bubbleHorizontalPadding * 2) - bubbleLeadingInset,
                    height: 190 - (bubbleVerticalPadding * 2)
                )
            }
            return measuredMessageContentSize(for: messageString, maxWidth: maximumBubbleContentWidth)
        }
        return resolvedTypingContentSize
    }

    private var maximumBubbleContentWidth: CGFloat {
        let resolvedWidth = availableBubbleWidth - (bubbleHorizontalPadding * 2) - bubbleLeadingInset
        return max(resolvedWidth, resolvedTypingContentSize.width)
    }

    private var bubbleMorphProgress: CGFloat {
        let progress = handoffProgress
        return progress * progress * (3 - (2 * progress))
    }

    private var isShowingMessageState: Bool {
        if case .message = presentation {
            return true
        }
        return false
    }

    private var interpolatedBubbleContentSize: CGSize {
        let start = resolvedTypingContentSize
        let end = resolvedMessageContentSize
        let progress = bubbleMorphProgress

        return CGSize(
            width: start.width + ((end.width - start.width) * progress),
            height: start.height + ((end.height - start.height) * progress)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                avatarView

                VStack(alignment: .leading, spacing: 2) {
                    if !isGroupedWithPrevious {
                        Text(nicknameText)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.leading, 10)
                            .frame(height: nicknameReservedHeight, alignment: .leading)
                            .opacity(nicknameOpacity)
                    }

                    bubbleBody
                        .containerRelativeFrame(
                            .horizontal,
                            count: 4,
                            span: 3,
                            spacing: 0,
                            alignment: .leading
                        )
                        .measureWidth { width in
                            availableBubbleWidth = width
                        }
                        .animation(.easeInOut(duration: 0.28), value: messageRevealProgress)
                        .animation(.easeInOut(duration: 0.28), value: typingFadeProgress)
                }
                .padding(.bottom, 8)

                Spacer(minLength: 0)
            }

            if case .typing = presentation {
                Text(typingStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .padding(.leading, 50) // 32 (avatar) + 8 (HStack spacing) + 10 (bubble inset)
                    .opacity(typingLayerOpacity)
            }
        }
        .padding(.top, isGroupedWithPrevious ? 2 : 10)
    }

    private var bubbleBody: some View {
        ZStack(alignment: .topLeading) {
            typingContent
                .opacity(typingLayerOpacity)
                .offset(y: typingLayerOffset)

            Text(messageText)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: maximumBubbleContentWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isMessageTextVisible ? 1 : 0)
        }
        .frame(
            width: interpolatedBubbleContentSize.width,
            height: interpolatedBubbleContentSize.height,
            alignment: .topLeading
        )
        .clipped()
        .padding(.vertical, bubbleVerticalPadding)
        .padding(.horizontal, bubbleHorizontalPadding)
        .padding(.leading, bubbleLeadingInset)
        .background(
            MessageBubble(showsTail: true)
                .fill(Color.secondary.opacity(0.2))
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        )
        .animation(.easeInOut(duration: 0.28), value: interpolatedBubbleContentSize)
        .animation(.easeOut(duration: 0.12), value: isMessageTextVisible)
        .onAppear {
            syncMessageTextVisibility()
        }
        .onChange(of: isShowingMessageState) {
            syncMessageTextVisibility()
        }
        .onDisappear {
            textRevealTask?.cancel()
        }
    }

    private var typingContent: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                TypingMorphDotView(index: index)
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 2)
    }

    private var typingLayerOpacity: CGFloat {
        switch presentation {
        case .typing(_, let isVisible):
            return isVisible ? 1 : 0
        case .message:
            return 1 - typingFadeProgress
        }
    }

    private var typingLayerOffset: CGFloat {
        switch presentation {
        case .typing(_, let isVisible):
            return isVisible ? 0 : -10
        case .message:
            return typingFadeProgress * -8
        }
    }

    @MainActor
    private func syncMessageTextVisibility() {
        textRevealTask?.cancel()

        switch presentation {
        case .typing:
            isMessageTextVisible = false
        case .message:
            isMessageTextVisible = false
            guard !isImageOnlyMessage else { return }
            textRevealTask = Task {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isMessageTextVisible = true
                }
            }
        }
    }

    private func measuredMessageContentSize(for text: String, maxWidth: CGFloat) -> CGSize {
        guard !text.isEmpty, maxWidth > 0 else { return resolvedTypingContentSize }

        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
        )

        let bounds = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        return CGSize(
            width: ceil(min(bounds.width, maxWidth)),
            height: ceil(bounds.height)
        )
    }

    @ViewBuilder
    private var avatarView: some View {
        if let user {
            if let icon = Image(data: user.icon) {
                icon
                    .resizable()
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 6)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        } else {
            Color.clear
                .frame(width: 32, height: 32)
                .padding(.bottom, 6)
        }
    }
}

private struct TypingMorphDotView: View {
    let index: Int

    private let cycleDuration: Double = 0.9
    private let phases: [Double] = [0.0, 0.18, 0.36]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let motion = centeredMotion(at: time + phases[index])
            let highlight = (motion + 1) / 2

            Circle()
                .fill(Color.primary.opacity(0.38))
                .frame(width: 7, height: 7)
                .scaleEffect(0.95 + (highlight * 0.07))
                .offset(y: -motion * 1.8)
                .opacity(0.55 + (highlight * 0.45))
        }
        .frame(width: 7, height: 10)
        .allowsHitTesting(false)
    }

    private func centeredMotion(at time: Double) -> CGFloat {
        let progress = (time.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
        return CGFloat(sin(progress * (.pi * 2)))
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private extension View {
    func measureWidth(onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self, perform: onChange)
    }
}

#if os(macOS)
private struct ChatListInteractionObserver: NSViewRepresentable {
    let onScrollInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollInteraction: onScrollInteraction)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScrollInteraction = onScrollInteraction
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onScrollInteraction: () -> Void
        private weak var attachedView: NSView?
        private weak var observedScrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []

        init(onScrollInteraction: @escaping () -> Void) {
            self.onScrollInteraction = onScrollInteraction
        }

        func attach(to view: NSView) {
            attachedView = view
            DispatchQueue.main.async { [weak self] in
                self?.refreshObservedScrollViewIfNeeded()
            }
        }

        func detach() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            observedScrollView = nil
            attachedView = nil
        }

        private func refreshObservedScrollViewIfNeeded() {
            guard let view = attachedView else { return }
            let scrollView = enclosingScrollView(from: view)
            guard scrollView !== observedScrollView else { return }

            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            observedScrollView = scrollView

            guard let scrollView else { return }
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    self?.onScrollInteraction()
                }
            )
        }

        private func enclosingScrollView(from view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate as? NSScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}
#endif
