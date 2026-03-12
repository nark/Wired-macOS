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
    @State private var animatedNewMessageID: UUID?
    @State private var revealNewMessage = true
    
    var chat: Chat
    var onUserInteraction: (() -> Void)? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                    if message.type == .say {
                        let previous = index > 0 ? chat.messages[index - 1] : nil
                        let next = index < (chat.messages.count - 1) ? chat.messages[index + 1] : nil
                        let sameAsPrevious = previous?.type == .say && previous?.user.id == message.user.id
                        let sameAsNext = next?.type == .say && next?.user.id == message.user.id

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
            }
#if os(macOS)
            .background(
                ChatListInteractionObserver {
                    onUserInteraction?()
                }
            )
#endif
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .textSelection(.enabled)
            .frame(maxHeight: .infinity)
            .onChange(of: chat.messages.count) {
                DispatchQueue.main.async {
                    if let lastID = chat.messages.last?.id {
                        animatedNewMessageID = lastID
                        revealNewMessage = false
                        DispatchQueue.main.async {
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
                    if let lastID = chat.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let lastID = chat.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
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
