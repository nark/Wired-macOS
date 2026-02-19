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
    @State private var messageHistory: [String] = []
    @State private var historyIndex: Int? = nil
    @State private var historyDraft: String = ""
    @State private var lastProgrammaticHistoryValue: String? = nil
    
    @AppStorage("SubstituteEmoji") var substituteEmoji: Bool = true
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
    var emojiSubstitutions: [String: String]
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ChatTopicView(chat: chat)
                    .environment(runtime)
                
                Divider()
                
                ChatMessagesView(chat: chat)
                    .environment(runtime)
                
                Divider()

#if os(macOS)
                ChatInputField(
                    text: $chatInput,
                    onSubmit: {
                        Task { await sendMessage() }
                    },
                    onHistoryUp: {
                        browseHistoryUp()
                    },
                    onHistoryDown: {
                        browseHistoryDown()
                    }
                )
                .padding(5)
#else
                TextField("", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(5)
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }
#endif
            }
#if os(macOS)
            Divider()
            
            if let chatID = runtime.selectedChatID,
               let chat = runtime.chats.first(where: { $0.id == chatID })
            {
                ChatUsersList(chat: chat)
                    .environment(runtime)
            }
#endif
        }
        .onAppear {
            runtime.resetUnreads(chat)
            
#if os(iOS)
            if chat.joined == false {
                Task {
                    try? await runtime.joinChat(chat.id)
                }
            }
#endif
        }
        .onChange(of: chatInput) { _, newValue in
            if lastProgrammaticHistoryValue == newValue {
                lastProgrammaticHistoryValue = nil
                return
            }
            historyIndex = nil
        }
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
    
    func sendMessage() async {
        do {
            let originalInput = chatInput
            let trimmed = originalInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if substituteEmoji {
                chatInput = chatInput.replacingEmoticons(using: emojiSubstitutions)
            }
            
            _ = try await runtime.sendChatMessage(chat.id, chatInput)
            messageHistory.append(trimmed)
            historyIndex = nil
            historyDraft = ""
            chatInput = ""
        } catch {
            runtime.lastError = error
        }
    }

    private func browseHistoryUp() {
        guard !messageHistory.isEmpty else { return }

        let targetIndex: Int
        if let historyIndex {
            guard historyIndex > 0 else { return }
            targetIndex = historyIndex - 1
        } else {
            historyDraft = chatInput
            targetIndex = messageHistory.count - 1
        }

        historyIndex = targetIndex
        let value = messageHistory[targetIndex]
        lastProgrammaticHistoryValue = value
        chatInput = value
    }

    private func browseHistoryDown() {
        guard let historyIndex else { return }

        if historyIndex < (messageHistory.count - 1) {
            let next = historyIndex + 1
            self.historyIndex = next
            let value = messageHistory[next]
            lastProgrammaticHistoryValue = value
            chatInput = value
        } else {
            self.historyIndex = nil
            lastProgrammaticHistoryValue = historyDraft
            chatInput = historyDraft
        }
    }
}

#if os(macOS)
private struct ChatInputField: NSViewRepresentable {
    @Binding var text: String

    let onSubmit: () -> Void
    let onHistoryUp: () -> Void
    let onHistoryDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.drawsBackground = true
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onHistoryUp = onHistoryUp
        context.coordinator.onHistoryDown = onHistoryDown
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, NSControlTextEditingDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        var onHistoryUp: (() -> Void)?
        var onHistoryDown: (() -> Void)?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        @objc func submit() {
            onSubmit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let event = NSApp.currentEvent else { return false }
            guard event.modifierFlags.contains(.command) else { return false }

            // Reliable path for Cmd+Up / Cmd+Down regardless of resolved selector.
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
                return false
            }
        }
    }
}
#endif
