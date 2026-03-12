//
//  ChatView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 24/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ChatView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var chat: Chat
    @State private var chatInput: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ChatTopicView(chat: chat)
                    .environment(runtime)
                
                Divider()
                
                ChatMessagesView(
                    chat: chat,
                    onUserInteraction: {
                        markCurrentChatAsReadIfNeeded()
                    }
                )
                    .environment(runtime)
                                
                HStack(alignment: .top, spacing: 0) {
                    ConversationComposer(
                        text: $chatInput,
                        placeholder: "Chat here…",
                        isEnabled: true,
                        onSend: { text in
                            do {
                                _ = try await runtime.sendChatMessage(chat.id, text)
                            } catch {
                                runtime.lastError = error
                            }
                        }
                    )
                    
                    Button {
#if os(macOS)
                        NSApp.orderFrontCharacterPalette(nil)
#endif
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.title3)
                    }
                    .foregroundColor(.gray)
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                }
                .background(.background)
            }
#if os(macOS)
            Divider()
            
            if let chatID = runtime.selectedChatID,
               let chat = runtime.chat(withID: chatID)
            {
                ChatUsersList(chat: chat)
                    .environment(runtime)
            }
#endif
        }
        .onAppear {
            markCurrentChatAsReadIfNeeded()
            
#if os(iOS)
            if chat.joined == false {
                Task {
                    try? await runtime.joinChat(chat.id)
                }
            }
#endif
        }
        .onChange(of: chatInput) { _, newValue in
            guard !newValue.isEmpty else { return }
            markCurrentChatAsReadIfNeeded()
        }
#if os(macOS)
        .background(
            ChatWindowInteractionObserver {
                markCurrentChatAsReadIfNeeded()
            }
        )
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ChatUsersList(chat: chat)
                        .environment(runtime)
                        .navigationTitle("Users")
                } label: {
                    Image(systemName: "person.2.fill")
                }

            }
            
#endif
        }
    }

    private func markCurrentChatAsReadIfNeeded() {
        guard runtime.selectedTab == .chats else { return }
        guard runtime.selectedChatID == chat.id else { return }
        guard chat.unreadMessagesCount > 0 else { return }
        runtime.resetUnreads(chat)
    }
}

struct ConversationComposer: View {
    @Binding var text: String

    let placeholder: String
    let isEnabled: Bool
    let onSend: (String) async -> Void

    @State private var messageHistory: [String] = []
    @State private var historyIndex: Int? = nil
    @State private var historyDraft: String = ""
    @State private var lastProgrammaticHistoryValue: String? = nil
    @State private var inputHeight: CGFloat = 22

    @AppStorage("SubstituteEmoji") private var substituteEmoji: Bool = true
    @AppStorageCodable(key: "EmojiSubstitutions", defaultValue: [
        ":-)": "😊",
        ":)":  "😊",
        ";-)": "😉",
        ";)":  "😉",
        ":-D": "😀",
        ":D":  "😀",
        "<3":  "❤️",
        "+1":  "👍"
    ])
    private var emojiSubstitutions: [String: String]

    var body: some View {
        Group {
#if os(macOS)
            ZStack(alignment: .leading) {
                ChatInputField(
                    text: $text,
                    dynamicHeight: $inputHeight,
                    onSubmit: {
                        submit()
                    },
                    onHistoryUp: {
                        browseHistoryUp()
                    },
                    onHistoryDown: {
                        browseHistoryDown()
                    }
                )

                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: inputHeight)
            .padding(5)
            .opacity(isEnabled ? 1.0 : 0.65)
            .allowsHitTesting(isEnabled)
#else
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .padding(5)
                .disabled(!isEnabled)
                .onSubmit {
                    submit()
                }
#endif
        }
        .onChange(of: text) { _, newValue in
            if lastProgrammaticHistoryValue == newValue {
                lastProgrammaticHistoryValue = nil
                return
            }
            historyIndex = nil
        }
    }

    private func submit() {
        guard isEnabled else { return }

        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        if substituteEmoji {
            value = value.replacingEmoticons(using: emojiSubstitutions)
        }

        let finalText = value
        Task { await onSend(finalText) }

        messageHistory.append(finalText)
        historyIndex = nil
        historyDraft = ""
        text = ""
        inputHeight = 22
    }

    private func browseHistoryUp() {
        guard !messageHistory.isEmpty else { return }

        let targetIndex: Int
        if let historyIndex {
            guard historyIndex > 0 else { return }
            targetIndex = historyIndex - 1
        } else {
            historyDraft = text
            targetIndex = messageHistory.count - 1
        }

        historyIndex = targetIndex
        let value = messageHistory[targetIndex]
        lastProgrammaticHistoryValue = value
        text = value
    }

    private func browseHistoryDown() {
        guard let historyIndex else { return }

        if historyIndex < (messageHistory.count - 1) {
            let next = historyIndex + 1
            self.historyIndex = next
            let value = messageHistory[next]
            lastProgrammaticHistoryValue = value
            text = value
        } else {
            self.historyIndex = nil
            lastProgrammaticHistoryValue = historyDraft
            text = historyDraft
        }
    }
}

#if os(macOS)
private struct ChatWindowInteractionObserver: NSViewRepresentable {
    let onWindowBecameKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowBecameKey: onWindowBecameKey)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWindowBecameKey = onWindowBecameKey
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onWindowBecameKey: () -> Void
        private weak var observedWindow: NSWindow?
        private weak var attachedView: NSView?
        private var observer: NSObjectProtocol?

        init(onWindowBecameKey: @escaping () -> Void) {
            self.onWindowBecameKey = onWindowBecameKey
        }

        func attach(to view: NSView) {
            attachedView = view
            DispatchQueue.main.async { [weak self] in
                self?.refreshObserverIfNeeded()
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            observedWindow = nil
            attachedView = nil
        }

        private func refreshObserverIfNeeded() {
            guard let window = attachedView?.window else { return }
            guard window !== observedWindow else { return }

            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }

            observedWindow = window
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onWindowBecameKey()
            }
        }
    }
}

private final class FocusableInputScrollView: NSScrollView {
    weak var focusTarget: NSTextView?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let focusTarget, self.window?.firstResponder !== focusTarget {
            self.window?.makeFirstResponder(focusTarget)
        }
    }
}

private struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat

    let onSubmit: () -> Void
    let onHistoryUp: () -> Void
    let onHistoryDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, dynamicHeight: $dynamicHeight, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusableInputScrollView(frame: .zero)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6
        scrollView.layer?.masksToBounds = true
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        textView.textContainerInset = NSSize(width: 6, height: 2)
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.maximumNumberOfLines = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.frame = NSRect(x: 0, y: 0, width: 200, height: dynamicHeight)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        scrollView.focusTarget = textView

        scrollView.documentView = textView
        context.coordinator.recomputeHeight()
        context.coordinator.applyTypingStyle()
        DispatchQueue.main.async {
            if let container = textView.textContainer {
                container.containerSize = NSSize(width: max(scrollView.contentSize.width, 1), height: CGFloat.greatestFiniteMagnitude)
            }
            context.coordinator.recomputeHeight()
        }
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        nsView.backgroundColor = .textBackgroundColor
        nsView.layer?.borderColor = NSColor.separatorColor.cgColor
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: max(nsView.contentSize.width, 1), height: CGFloat.greatestFiniteMagnitude)
        }
        if textView.string != text {
            textView.string = text
            // History navigation can change text in one state update; force layout on next runloop too.
            DispatchQueue.main.async {
                context.coordinator.recomputeHeight()
            }
        }
        context.coordinator.recomputeHeight()
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onHistoryUp = onHistoryUp
        context.coordinator.onHistoryDown = onHistoryDown
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var dynamicHeight: CGFloat
        var onSubmit: () -> Void
        var onHistoryUp: (() -> Void)?
        var onHistoryDown: (() -> Void)?
        weak var textView: NSTextView?
        private let minimumLineCount: CGFloat = 1
        private let maximumLineCount: CGFloat = 5
        private let minimumHeight: CGFloat = 22

        init(text: Binding<String>, dynamicHeight: Binding<CGFloat>, onSubmit: @escaping () -> Void) {
            self._text = text
            self._dynamicHeight = dynamicHeight
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            applyTypingStyle()
            recomputeHeight()
        }

        func textDidBeginEditing(_ notification: Notification) {
            applyTypingStyle()
        }

        func applyTypingStyle() {
            guard let textView else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
            textView.typingAttributes = attrs
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
        }

        func recomputeHeight() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            if let visibleWidth = textView.enclosingScrollView?.contentSize.width, visibleWidth > 0 {
                let targetWidth = max(visibleWidth, 1)
                container.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
                if textView.frame.width != targetWidth {
                    textView.setFrameSize(NSSize(width: targetWidth, height: textView.frame.height))
                }
            }
            layoutManager.ensureLayout(for: container)

            let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: NSFont.systemFontSize))
            let verticalInset = textView.textContainerInset.height * 2
            let minHeight = max(minimumHeight, lineHeight * minimumLineCount + verticalInset + 2)
            let maxHeight = lineHeight * maximumLineCount + verticalInset + 4
            if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dynamicHeight = minHeight
                return
            }
            let usedRect = layoutManager.usedRect(for: container)
            let contentHeight = ceil(usedRect.height + verticalInset + 2)
            dynamicHeight = min(max(contentHeight, minHeight), maxHeight)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let event = NSApp.currentEvent else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.command) {
                switch event.keyCode {
                case 126: // up arrow
                    onHistoryUp?()
                    return true
                case 125: // down arrow
                    onHistoryDown?()
                    return true
                default:
                    break
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if flags.contains(.shift) || flags.contains(.option) {
                    return false
                } else {
                    onSubmit()
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                // Option+Return should always insert a line break.
                return false
            }

            if flags.contains(.command) {
                switch commandSelector {
                case #selector(NSResponder.moveUp(_:)),
                     #selector(NSResponder.moveToBeginningOfDocument(_:)):
                    onHistoryUp?()
                    return true
                case #selector(NSResponder.moveDown(_:)),
                     #selector(NSResponder.moveToEndOfDocument(_:)):
                    onHistoryDown?()
                    return true
                default:
                    break
                }
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                return false
            }

            return false
        }
    }
}
#endif
