//
//  MessagesView.swift
//  Wired 3
//

import SwiftUI

struct MessagesView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @State private var conversationIDPendingDeletion: UUID?

    private var selectedConversation: MessageConversation? {
        runtime.messageConversation(withID: runtime.selectedMessageConversationID)
    }

    private var directConversations: [MessageConversation] {
        runtime.messageConversations.filter { $0.kind == .direct }
    }

    private var broadcastConversations: [MessageConversation] {
        runtime.messageConversations.filter { $0.kind == .broadcast }
    }

    private var pendingDeletionConversation: MessageConversation? {
        guard let conversation = runtime.messageConversation(withID: conversationIDPendingDeletion),
              conversation.kind == .direct else {
            return nil
        }
        return conversation
    }

    var body: some View {
#if os(macOS)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: Binding(
                    get: { runtime.selectedMessageConversationID },
                    set: { runtime.selectedMessageConversationID = $0 }
                )) {
                    Section("Private Messages") {
                        ForEach(directConversations) { conversation in
                            MessageConversationRow(conversation: conversation)
                                .environment(runtime)
                                .tag(conversation.id)
                                .contextMenu {
                                    Button("Delete") {
                                        conversationIDPendingDeletion = conversation.id
                                    }
                                }
                        }
                    }

                    Section("Broadcasts") {
                        ForEach(broadcastConversations) { conversation in
                            MessageConversationRow(conversation: conversation)
                                .environment(runtime)
                                .tag(conversation.id)
                        }
                    }
                }
                .listStyle(.plain)

                Divider()

                HStack {
                    Button {
                        if selectedConversation?.kind == .direct {
                            conversationIDPendingDeletion = runtime.selectedMessageConversationID
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedConversation?.kind != .direct)
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 7)
            }
            .frame(width: 260)

            Divider()

            Group {
                if let conversation = selectedConversation {
                    MessageConversationDetailView(conversation: conversation)
                        .environment(runtime)
                } else {
                    ContentUnavailableView(
                        "No Conversation",
                        systemImage: "ellipsis.message",
                        description: Text("Open a conversation from the users list.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            _ = runtime.ensureBroadcastConversation()
            if runtime.selectedMessageConversationID == nil {
                runtime.selectedMessageConversationID = runtime.messageConversations.first?.id
            }
            if let selectedConversation {
                runtime.resetUnreads(selectedConversation)
            }
        }
        .onChange(of: runtime.selectedMessageConversationID) { _, newValue in
            if let conversation = runtime.messageConversation(withID: newValue) {
                runtime.resetUnreads(conversation)
            }
        }
        .confirmationDialog(
            "Delete Conversation?",
            isPresented: Binding(
                get: { pendingDeletionConversation != nil },
                set: { isPresented in
                    if !isPresented {
                        conversationIDPendingDeletion = nil
                    }
                }
            ),
            presenting: pendingDeletionConversation
        ) { conversation in
            Button("Delete \"\(conversation.title)\"", role: .destructive) {
                runtime.deleteMessageConversation(withID: conversation.id)
                conversationIDPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                conversationIDPendingDeletion = nil
            }
        } message: { conversation in
            Text("This will permanently remove \"\(conversation.title)\" and its messages.")
        }
#else
        NavigationStack {
            List {
                Section("Private Messages") {
                    ForEach(directConversations) { conversation in
                        NavigationLink {
                            MessageConversationDetailView(conversation: conversation)
                                .environment(runtime)
                                .navigationTitle(conversation.title)
                        } label: {
                            MessageConversationRow(conversation: conversation)
                                .environment(runtime)
                        }
                    }
                }

                Section("Broadcasts") {
                    ForEach(broadcastConversations) { conversation in
                        NavigationLink {
                            MessageConversationDetailView(conversation: conversation)
                                .environment(runtime)
                                .navigationTitle(conversation.title)
                        } label: {
                            MessageConversationRow(conversation: conversation)
                                .environment(runtime)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onAppear {
                _ = runtime.ensureBroadcastConversation()
            }
        }
#endif
    }
}
