//
//  MessageConversationDetailView.swift
//  Wired 3
//

import SwiftUI

struct MessageConversationDetailView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    let conversation: MessageConversation
    var searchText: String = ""

    private var inputText: String {
        runtime.messageDrafts[conversation.id] ?? ""
    }

    private var inputTextBinding: Binding<String> {
        Binding(
            get: { runtime.messageDrafts[conversation.id] ?? "" },
            set: { runtime.messageDrafts[conversation.id] = $0.isEmpty ? nil : $0 }
        )
    }

    private var composerOverlayInset: CGFloat {
        #if os(macOS)
        58
        #else
        76
        #endif
    }

    private var canSend: Bool {
        runtime.canSendMessage(to: conversation)
    }

    private var placeholder: String {
        guard canSend else {
            if conversation.kind == .broadcast {
                return "No broadcast permission"
            }
            return "User unavailable"
        }
        if conversation.kind == .broadcast {
            return "Broadcast to all online users…"
        }
        return "Type message here…"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MessageConversationMessagesView(
                conversation: conversation,
                searchText: searchText,
                bottomOverlayInset: composerOverlayInset
            )
            .environment(runtime)

            HStack(alignment: .top, spacing: 0) {
                ConversationComposer(
                    text: inputTextBinding,
                    placeholder: placeholder,
                    isEnabled: canSend,
                    onSend: { text in
                        do {
                            switch conversation.kind {
                            case .direct:
                                try await runtime.sendPrivateMessage(text, in: conversation)
                            case .broadcast:
                                try await runtime.sendBroadcastMessage(text)
                            }
                        } catch {
                            runtime.lastError = error
                        }
                    }
                )
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
            .backgroundEdgeFade(top: 0, bottom: 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .contentMargins(.bottom, 15, for: .scrollIndicators)
        .background(.background)
        .onAppear {
            runtime.resetUnreads(conversation)
        }
    }
}
