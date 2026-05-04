//
//  ChatView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 24/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ChatView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    var chat: Chat
    var searchText: String = ""
    @State private var typingDebounceTask: Task<Void, Never>?
    @State private var typingRefreshTask: Task<Void, Never>?
#if os(iOS)
    @State private var chatScrollTrigger: Int = 0
#endif
#if os(macOS)
    @State private var isAttachmentDropTargeted = false
    @AppStorage("userListWidth") private var userListWidth: Double = 200
#endif

    private var chatInput: String {
        runtime.chatDrafts[chat.id] ?? ""
    }

    private var chatDraftAttachments: [ChatDraftAttachment] {
        runtime.chatDraftAttachments[chat.id] ?? []
    }

    private var chatInputBinding: Binding<String> {
        Binding(
            get: { runtime.chatDrafts[chat.id] ?? "" },
            set: { runtime.chatDrafts[chat.id] = $0.isEmpty ? nil : $0 }
        )
    }

    private var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var topicOverlayInset: CGFloat {
        #if os(macOS)
        76
        #else
        84
        #endif
    }

    private var composerOverlayInset: CGFloat {
        let attachmentInset: CGFloat = chatDraftAttachments.isEmpty ? 0 : 42
#if os(macOS)
        return 58 + attachmentInset
#else
        return 76 + attachmentInset
#endif
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChatMessagesView(
                    chat: chat,
                    searchText: searchText,
                    topOverlayInset: topicOverlayInset,
                    bottomOverlayInset: composerOverlayInset,
                    keyboardShowTrigger: {
#if os(iOS)
                        chatScrollTrigger
#else
                        0
#endif
                    }(),
                    onUserInteraction: {
                        markCurrentChatAsReadIfNeeded()
                    }
                )
                .environment(runtime)
#if os(iOS)
                .padding([.horizontal], 10)
#endif

                ChatTopicView(chat: chat)
                    .environment(runtime)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 6) {
                    if !chatDraftAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(chatDraftAttachments) { attachment in
                                    ChatDraftAttachmentChipView(attachment: attachment) {
                                        runtime.removeChatDraftAttachment(attachment, for: chat.id)
                                    }
                                }
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 8)
                        }
                    }

                    HStack(alignment: .top, spacing: 0) {
                        ConversationComposer(
                            text: chatInputBinding,
                            placeholder: chatDraftAttachments.isEmpty ? "Chat here…" : "Add a message or press Return to send…",
                            isEnabled: true,
                            allowsEmptySubmit: !chatDraftAttachments.isEmpty,
                            onSend: { text in
                                await runtime.setChatTyping(chatID: chat.id, isTyping: false)
                                do {
                                    _ = try await runtime.sendChatMessage(chat.id, text, attachments: chatDraftAttachments)
                                    runtime.clearChatDraftAttachments(for: chat.id)
                                } catch {
                                    runtime.chatDrafts[chat.id] = text
                                    runtime.lastError = error
                                }
                            },
                            onTextChanged: { newValue in
                                handleComposerTextChanged(newValue)
                            },
                            onDisappear: {
                                stopTypingUpdates(sendStopSignal: true)
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

#if os(macOS)
                        Button {
                            NSApp.orderFrontCharacterPalette(nil)
                        } label: {
                            Image(systemName: "face.smiling")
                                .font(.title3)
                        }
                        .foregroundColor(.gray)
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
#endif
                    }
                }
                .backgroundEdgeFade(top: 0, bottom: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
#if os(macOS)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(isAttachmentDropTargeted ? 0.9 : 0), lineWidth: 4)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor.opacity(isAttachmentDropTargeted ? 0.08 : 0))
                    )
                    .padding(8)
                    .allowsHitTesting(false)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isAttachmentDropTargeted) { providers in
                handleFileDrop(providers: providers)
            }
#endif
            .contentMargins(.bottom, 30, for: .scrollIndicators)

#if os(macOS)
            DraggableSidebarDivider(width: $userListWidth, minWidth: 120, maxWidth: 400, direction: -1)

            if let chatID = runtime.selectedChatID,
               let chat = runtime.chat(withID: chatID) {
                ChatUsersList(chat: chat)
                    .environment(runtime)
                    .frame(width: userListWidth)
            }
#endif
        }
        .onAppear {
            markCurrentChatAsReadIfNeeded()

#if os(iOS)
            if chat.joined == false {
                Task {
                    do {
                        try await runtime.joinChat(chat.id)
                    } catch {
                        runtime.lastError = error
                    }
                }
            }
#endif
        }
        .onChange(of: chatInput) { _, newValue in
            guard !newValue.isEmpty else { return }
            markCurrentChatAsReadIfNeeded()
        }
        .onChange(of: runtime.selectedChatID) { _, newValue in
            if newValue != chat.id {
                stopTypingUpdates(sendStopSignal: true)
            }
        }
        .onDisappear {
            stopTypingUpdates(sendStopSignal: true)
        }
#if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            chatScrollTrigger += 1
        }
#endif
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

    @MainActor
    private func markCurrentChatAsReadIfNeeded() {
        guard runtime.selectedTab == .chats else { return }
        guard runtime.selectedChatID == chat.id else { return }
        guard chat.unreadMessagesCount > 0 else { return }
        runtime.resetUnreads(chat)
    }

    @MainActor
    private func handleComposerTextChanged(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            stopTypingUpdates(sendStopSignal: true)
            return
        }

        guard typingDebounceTask == nil, typingRefreshTask == nil else { return }
        scheduleTypingStart()
    }

    @MainActor
    private func scheduleTypingStart() {
        typingDebounceTask?.cancel()

        let chatID = chat.id
        typingDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let trimmed = await MainActor.run {
                chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !trimmed.isEmpty else {
                await MainActor.run {
                    typingDebounceTask = nil
                }
                return
            }

            await runtime.setChatTyping(chatID: chatID, isTyping: true)

            await MainActor.run {
                typingDebounceTask = nil
                startTypingRefreshLoop(for: chatID)
            }
        }
    }

    @MainActor
    private func startTypingRefreshLoop(for chatID: UInt32) {
        typingRefreshTask?.cancel()

        typingRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                let trimmed = await MainActor.run {
                    chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                guard !trimmed.isEmpty else {
                    await MainActor.run {
                        stopTypingUpdates(sendStopSignal: true)
                    }
                    return
                }

                await runtime.setChatTyping(chatID: chatID, isTyping: true)
            }
        }
    }

    @MainActor
    private func stopTypingUpdates(sendStopSignal: Bool) {
        typingDebounceTask?.cancel()
        typingDebounceTask = nil
        typingRefreshTask?.cancel()
        typingRefreshTask = nil

        guard sendStopSignal else { return }

        let chatID = chat.id
        Task {
            await runtime.setChatTyping(chatID: chatID, isTyping: false)
        }
    }

#if os(macOS)
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else {
            return false
        }

        for provider in fileProviders {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let error {
                    Task { @MainActor in
                        runtime.lastError = error
                    }
                    return
                }

                guard let data,
                      let fileURL = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    do {
                        try runtime.addChatDraftAttachment(fileURL, for: chat.id)
                    } catch {
                        runtime.lastError = error
                    }
                }
            }
        }

        return true
    }
#endif
}

struct ConversationComposer: View {
    @Binding var text: String

    let placeholder: String
    let isEnabled: Bool
    var allowsEmptySubmit: Bool = false
    let onSend: (String) async -> Void
    var onTextChanged: ((String) -> Void)?
    var onDisappear: (() -> Void)?

    @State private var messageHistory: [String] = []
    @State private var historyIndex: Int?
    @State private var historyDraft: String = ""
    @State private var lastProgrammaticHistoryValue: String?
    @State private var inputHeight: CGFloat = 22
    @State private var commandSuggestions: [ChatCommand] = []
    @State private var selectedSuggestionIndex: Int = 0

    @AppStorage("SubstituteEmoji") private var substituteEmoji: Bool = true
    @AppStorageCodable(key: "EmojiSubstitutions", defaultValue: [
        ":-)": "😊",
        ":)": "😊",
        ";-)": "😉",
        ";)": "😉",
        ":-D": "😀",
        ":D": "😀",
        "<3": "❤️",
        "+1": "👍"
    ])
    private var emojiSubstitutions: [String: String]

    var body: some View {
        Group {
#if os(macOS)
            VStack(spacing: 0) {
                if !commandSuggestions.isEmpty {
                    ChatCommandSuggestionsView(
                        suggestions: commandSuggestions,
                        selectedIndex: selectedSuggestionIndex
                    ) { command in
                        text = completionText(for: command)
                        commandSuggestions = []
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ZStack(alignment: .leading) {
                    ChatInputField(
                        text: $text,
                        dynamicHeight: $inputHeight,
                        isEnabled: isEnabled,
                        allowsEmptySubmit: allowsEmptySubmit,
                        onSubmit: {
                            submit()
                        },
                        onHistoryUp: {
                            browseHistoryUp()
                        },
                        onHistoryDown: {
                            browseHistoryDown()
                        },
                        onSuggestionUp: {
                            navigateSuggestion(by: -1)
                        },
                        onSuggestionDown: {
                            navigateSuggestion(by: 1)
                        },
                        onSuggestionSelect: {
                            applySelectedSuggestion()
                        },
                        onSuggestionDismiss: {
                            commandSuggestions = []
                        },
                        hasSuggestions: !commandSuggestions.isEmpty
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
            }
#else
            TextField("", text: $text, prompt: Text(placeholder), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.background)
                        .shadow(color: .gray.opacity(0.3), radius: 10)
                )
                .padding(10)
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
            onTextChanged?(newValue)
            updateCommandSuggestions(for: newValue)
        }
        .onDisappear {
            onDisappear?()
        }
    }

    private func submit() {
        guard isEnabled else { return }

        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty || allowsEmptySubmit else { return }

        if substituteEmoji, !value.isEmpty {
            value = value.replacingEmoticons(using: emojiSubstitutions)
        }

        let finalText = value
        Task { await onSend(finalText) }

        if !finalText.isEmpty {
            messageHistory.append(finalText)
        }
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

    private func updateCommandSuggestions(for input: String) {
        let normalized = input.trimmingCharacters(in: .newlines)
        guard normalized.hasPrefix("/") else {
            commandSuggestions = []
            return
        }

        guard !normalized.contains(" ") else {
            commandSuggestions = []
            return
        }

        let query = normalized.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            commandSuggestions = []
            return
        }

        let filtered = ChatCommand.allCases.filter { $0.rawValue.hasPrefix(query) }
        commandSuggestions = filtered
        selectedSuggestionIndex = 0
    }

    private func navigateSuggestion(by delta: Int) {
        guard !commandSuggestions.isEmpty else { return }
        let count = commandSuggestions.count
        selectedSuggestionIndex = (selectedSuggestionIndex + delta + count) % count
    }

    private func applySelectedSuggestion() {
        guard !commandSuggestions.isEmpty else { return }
        let command = commandSuggestions[selectedSuggestionIndex]
        text = completionText(for: command)
        commandSuggestions = []
    }

    private func completionText(for command: ChatCommand) -> String {
        command.hint.isEmpty ? command.rawValue : command.rawValue + " "
    }
}

#if os(macOS)
struct DraggableSidebarDivider: View {
    @Binding var width: Double
    var minWidth: Double = 120
    var maxWidth: Double = 500
    // +1: panel is left of divider (drag right = wider)
    // -1: panel is right of divider (drag left = wider)
    var direction: Double = 1

    @State private var isDragging = false
    @State private var dragStartWidth: Double = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartWidth = width
                            }
                            let delta = Double(value.translation.width)
                            width = max(minWidth, min(maxWidth, dragStartWidth + direction * delta))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        }
    }
}
#endif

#if os(macOS)
private struct ChatCommandSuggestionsView: View {
    let suggestions: [ChatCommand]
    let selectedIndex: Int
    let onSelect: (ChatCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.rawValue) { index, command in
                ChatCommandSuggestionRow(
                    command: command,
                    isKeyboardSelected: index == selectedIndex,
                    onSelect: { onSelect(command) }
                )
                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, 10)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: -4)
    }
}

private struct ChatCommandSuggestionRow: View {
    let command: ChatCommand
    let isKeyboardSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(command.rawValue)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            if !command.hint.isEmpty {
                Text(" \(command.hint)")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(command.usage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isHovered || isKeyboardSelected)
                ? Color.accentColor.opacity(isKeyboardSelected ? 0.18 : 0.10)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}
#endif

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
    var isEnabled: Bool = true
    var allowsEmptySubmit: Bool = false

    let onSubmit: () -> Void
    let onHistoryUp: () -> Void
    let onHistoryDown: () -> Void
    var onSuggestionUp: (() -> Void)?
    var onSuggestionDown: (() -> Void)?
    var onSuggestionSelect: (() -> Void)?
    var onSuggestionDismiss: (() -> Void)?
    var hasSuggestions: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            dynamicHeight: $dynamicHeight,
            allowsEmptySubmit: allowsEmptySubmit,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusableInputScrollView(frame: .zero)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 10
        scrollView.layer?.masksToBounds = true
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.isEditable = isEnabled
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
        context.coordinator.isEnabled = isEnabled
        scrollView.focusTarget = textView

        scrollView.documentView = textView
        context.coordinator.applyTypingStyle()
        DispatchQueue.main.async {
            if let container = textView.textContainer {
                container.containerSize = NSSize(width: max(scrollView.contentSize.width, 1), height: CGFloat.greatestFiniteMagnitude)
            }
            context.coordinator.recomputeHeight()
        }
        if isEnabled {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.textBinding = $text
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
        DispatchQueue.main.async {
            context.coordinator.recomputeHeight()
        }
        if isEnabled != context.coordinator.isEnabled {
            context.coordinator.isEnabled = isEnabled
            textView.isEditable = isEnabled
            if !isEnabled {
                if textView.window?.firstResponder === textView {
                    textView.window?.makeFirstResponder(nil)
                }
            } else {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onHistoryUp = onHistoryUp
        context.coordinator.onHistoryDown = onHistoryDown
        context.coordinator.onSuggestionUp = onSuggestionUp
        context.coordinator.onSuggestionDown = onSuggestionDown
        context.coordinator.onSuggestionSelect = onSuggestionSelect
        context.coordinator.onSuggestionDismiss = onSuggestionDismiss
        context.coordinator.hasSuggestions = hasSuggestions
        context.coordinator.allowsEmptySubmit = allowsEmptySubmit
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        var dynamicHeightBinding: Binding<CGFloat>
        var allowsEmptySubmit: Bool
        var onSubmit: () -> Void
        var onHistoryUp: (() -> Void)?
        var onHistoryDown: (() -> Void)?
        var onSuggestionUp: (() -> Void)?
        var onSuggestionDown: (() -> Void)?
        var onSuggestionSelect: (() -> Void)?
        var onSuggestionDismiss: (() -> Void)?
        var hasSuggestions: Bool = false
        var isEnabled: Bool = true
        weak var textView: NSTextView?
        private let minimumLineCount: CGFloat = 1
        private let maximumLineCount: CGFloat = 5
        private let minimumHeight: CGFloat = 22

        init(
            text: Binding<String>,
            dynamicHeight: Binding<CGFloat>,
            allowsEmptySubmit: Bool,
            onSubmit: @escaping () -> Void
        ) {
            self.textBinding = text
            self.dynamicHeightBinding = dynamicHeight
            self.allowsEmptySubmit = allowsEmptySubmit
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            textBinding.wrappedValue = textView.string
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
                dynamicHeightBinding.wrappedValue = minHeight
                return
            }
            let usedRect = layoutManager.usedRect(for: container)
            let contentHeight = ceil(usedRect.height + verticalInset + 2)
            dynamicHeightBinding.wrappedValue = min(max(contentHeight, minHeight), maxHeight)
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

            if hasSuggestions {
                switch commandSelector {
                case #selector(NSResponder.moveUp(_:)):
                    if !flags.contains(.command) {
                        onSuggestionUp?()
                        return true
                    }
                case #selector(NSResponder.moveDown(_:)):
                    if !flags.contains(.command) {
                        onSuggestionDown?()
                        return true
                    }
                case #selector(NSResponder.insertTab(_:)),
                     #selector(NSResponder.insertNewline(_:)):
                    onSuggestionSelect?()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    onSuggestionDismiss?()
                    return true
                default:
                    break
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if flags.contains(.shift) || flags.contains(.option) {
                    return false
                } else {
                    let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty || allowsEmptySubmit else { return true }
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
