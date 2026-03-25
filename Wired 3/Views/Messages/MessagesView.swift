//
//  MessagesView.swift
//  Wired 3
//

import SwiftUI

struct MessagesView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @State private var conversationIDPendingDeletion: UUID?
    @State private var searchText: String = ""
    @State private var isShowingSearchProgress = false
    
    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    private var filteredConversations: [MessageConversation] {
        runtime.messageConversations.filter { $0.matchesSearch(normalizedSearchText) }
    }

    private var selectedConversation: MessageConversation? {
        guard let conversation = runtime.messageConversation(withID: runtime.selectedMessageConversationID) else {
            return nil
        }

        guard conversation.matchesSearch(normalizedSearchText) else {
            return nil
        }

        return conversation
    }

    private var directConversations: [MessageConversation] {
        filteredConversations.filter { $0.kind == .direct }
    }

    private var broadcastConversations: [MessageConversation] {
        filteredConversations.filter { $0.kind == .broadcast }
    }

    private var hasSearchResults: Bool {
        !filteredConversations.isEmpty
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
                    if !directConversations.isEmpty {
                        Section("Private Messages") {
                            ForEach(directConversations) { conversation in
                                MessageConversationRow(
                                    conversation: conversation,
                                    searchText: normalizedSearchText
                                )
                                    .environment(runtime)
                                    .tag(conversation.id)
                                    .contextMenu {
                                        Button("Delete") {
                                            conversationIDPendingDeletion = conversation.id
                                        }
                                    }
                            }
                        }
                    }

                    if !broadcastConversations.isEmpty {
                        Section("Broadcasts") {
                            ForEach(broadcastConversations) { conversation in
                                MessageConversationRow(
                                    conversation: conversation,
                                    searchText: normalizedSearchText
                                )
                                    .environment(runtime)
                                    .tag(conversation.id)
                            }
                        }
                    }

                    if isSearching && !hasSearchResults {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("No conversation or message matches \"\(normalizedSearchText)\".")
                        )
                        .listRowInsets(EdgeInsets(top: 24, leading: 12, bottom: 24, trailing: 12))
                        .listRowSeparator(.hidden)
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

                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                        .opacity(isShowingSearchProgress ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isShowingSearchProgress)
                        .help("Updating message search results")
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 7)
            }
            .frame(width: 260)

            Divider()

            Group {
                if let conversation = selectedConversation {
                    MessageConversationDetailView(
                        conversation: conversation,
                        searchText: normalizedSearchText
                    )
                        .environment(runtime)
                } else if isSearching && !hasSearchResults {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search.")
                    )
                } else if isSearching {
                    ContentUnavailableView(
                        "Select a Conversation",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Choose a conversation from the filtered results.")
                    )
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
        .searchable(text: $searchText)
        .onChange(of: normalizedSearchText) { _, query in
            guard !query.isEmpty else {
                isShowingSearchProgress = false
                return
            }

            isShowingSearchProgress = true

            DispatchQueue.main.async {
                if normalizedSearchText == query {
                    isShowingSearchProgress = false
                }
            }
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
                if !directConversations.isEmpty {
                    Section("Private Messages") {
                        ForEach(directConversations) { conversation in
                            NavigationLink {
                                MessageConversationDetailView(
                                    conversation: conversation,
                                    searchText: normalizedSearchText
                                )
                                    .environment(runtime)
                                    .navigationTitle(conversation.title)
                            } label: {
                                MessageConversationRow(
                                    conversation: conversation,
                                    searchText: normalizedSearchText
                                )
                                    .environment(runtime)
                            }
                        }
                    }
                }

                if !broadcastConversations.isEmpty {
                    Section("Broadcasts") {
                        ForEach(broadcastConversations) { conversation in
                            NavigationLink {
                                MessageConversationDetailView(
                                    conversation: conversation,
                                    searchText: normalizedSearchText
                                )
                                    .environment(runtime)
                                    .navigationTitle(conversation.title)
                            } label: {
                                MessageConversationRow(
                                    conversation: conversation,
                                    searchText: normalizedSearchText
                                )
                                    .environment(runtime)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isSearching && !hasSearchResults {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No conversation or message matches \"\(normalizedSearchText)\".")
                    )
                }
            }
            .searchable(text: $searchText)
            .onAppear {
                _ = runtime.ensureBroadcastConversation()
            }
        }
#endif
    }
}
