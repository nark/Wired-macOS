//
//  ChatTopicView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatTopicView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(ConnectionRuntime.self) private var runtime
    
    @State private var topicText = ""
    @State private var showTopicSheet = false
    @State private var isTopicExpanded = false
    
    @State private var hoverTimer: Timer? = nil
    
    var chat: Chat

    private var canSetTopic: Bool {
        runtime.hasPrivilege("wired.account.chat.set_topic")
    }

    private var hasTopic: Bool {
        !(chat.topic?.topic ?? "").isEmpty
    }

    private var topicTimestampFormat: Date.FormatStyle {
        .dateTime
            .day(.twoDigits)
            .month(.abbreviated)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: hasTopic ? .top : .center) {
                if let topic = chat.topic, topic.topic != "" {
                    VStack(alignment: .leading, spacing: 0) {
                        (
                            Text("Topic: ")
                                .fontWeight(.semibold)
                            +
                            Text(topic.topic)
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(isTopicExpanded ? nil : 1)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    //.help(chat.topic?.topic ?? "")
                } else {
                    Text("*No topic set*")
                        .multilineTextAlignment(.leading)
                        .lineLimit(isTopicExpanded ? nil : 1)
                        .font(.system(size: 13))
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                }
                
                Spacer()

                HStack(spacing: 0) {
                    if let topic = chat.topic, topic.topic != "" {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(topic.nick)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(topic.time.formatted(topicTimestampFormat))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 10)
                        .padding(.vertical, 6)
                    }

                    Rectangle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.08 : 0.22))
                        .frame(width: 1)
                        .frame(height: 24)

                    Button {
                        topicText = ""
                        showTopicSheet.toggle()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .frame(width: 36, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSetTopic)
                    .opacity(canSetTopic ? 1.0 : 0.45)
                    .padding(.horizontal, 4)
                }
                .background {
                    Group {
                        if let topic = chat.topic, topic.topic != "" {
                            if isTopicExpanded {
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading: 0,
                                        bottomLeading: 8,
                                        bottomTrailing: 0,
                                        topTrailing: 19
                                    ),
                                    style: .continuous
                                )
                                .fill(.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
                            } else {
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading: 0,
                                        bottomLeading: 0,
                                        bottomTrailing: 19,
                                        topTrailing: 19
                                    ),
                                    style: .continuous
                                )
                                .fill(.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
                            }
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .sheet(isPresented: $showTopicSheet, content: {
                NavigationStack {
                    Form {
                        TextEditor(text: $topicText)
                            .frame(minHeight: 60)
                            .padding(10)
                    }
                    .navigationTitle("Set Topic")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) {
                                showTopicSheet = false
                            }
                        }
                        
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                showTopicSheet = false
                                
                                if topicText != "" {
                                    Task {
                                        try await runtime.setChatTopic(chat.id, topic: topicText)
                                    }
                                }
                            }
                            .disabled(topicText == "")
                        }
                    }
                }
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(.background.opacity(isTopicExpanded ? 1.0 : 0.9))
                    .stroke(.gray, style: StrokeStyle(lineWidth: 0.3 / displayScale), antialiased: true)
                    .shadow(
                        color: colorScheme == .dark
                            ? .black.opacity(0.3)
                            : .gray.opacity(0.3),
                        radius: 4
                    )
            )
            
#if os(macOS)
            .onHover { isHover in
                if isHover && hoverTimer == nil {
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.isTopicExpanded = true
                            self.hoverTimer = nil
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTopicExpanded = false
                        hoverTimer?.invalidate()
                        hoverTimer = nil
                    }
                }
            }
#elseif os(iOS)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isTopicExpanded.toggle()
                }
            }
#endif
            .animation(.easeInOut(duration: 0.18), value: isTopicExpanded)
            .padding(8)
            .padding(.bottom, 12)
            .padding(.horizontal, 12)
#if os(macOS)
            .padding(.top, 5)
#endif
        }
        //.background(.clear)
        .backgroundEdgeFade(top: 30, bottom: 0)
    }
}
