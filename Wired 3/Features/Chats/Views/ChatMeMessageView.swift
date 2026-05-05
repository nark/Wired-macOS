//
//  ChatMessageView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatMeMessageView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @AppStorage("TimestampEveryMessage") var timestampEveryMessage: Bool = false

    var message: ChatEvent
    var selectedImageSource: ChatImageQuickLookSource?
    var onSelectImage: ((ChatImageQuickLookSource) -> Void)?
    var onOpenQuickLook: ((ChatImageQuickLookSource) -> Void)?

    private var imageAttachments: [ChatAttachmentDescriptor] {
        message.attachments.filter(\.isImage)
    }

    private var fileAttachments: [ChatAttachmentDescriptor] {
        message.attachments.filter { !$0.isImage }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom) {
                if timestampEveryMessage {
                    RelativeDateText(date: message.date)
                        .foregroundStyle(.clear)
                        .monospacedDigit()
                        .font(.caption)
                }

                Spacer()

                (
                    Text("**\(message.user.nick)** ")
                    +
                    Text(message.text.attributedWithDetectedLinks(linkColor: .blue))
                )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.gray)
                    .font(.caption)

                Spacer()

                if timestampEveryMessage {
                    HoverableRelativeDateText(date: message.date)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                        .font(.caption)
                }
            }

            ForEach(imageAttachments, id: \.id) { attachment in
                let source = ChatImageQuickLookSource.attachment(attachment)
                HStack {
                    Spacer()
                    ChatAttachmentImageBubbleView(
                        attachment: attachment,
                        isFromYou: false,
                        showsTail: false,
                        isSelected: selectedImageSource?.selectionID == source.selectionID,
                        onSelect: {
                            onSelectImage?(source)
                        },
                        onOpenQuickLook: {
                            onOpenQuickLook?(source)
                        }
                    )
                    Spacer()
                }
            }

            ForEach(fileAttachments, id: \.id) { attachment in
                HStack {
                    Spacer()
                    ChatAttachmentFileBubbleView(attachment: attachment, isFromYou: false, showsTail: false)
                    Spacer()
                }
            }
        }
        .listRowSeparator(.hidden)
        .id(message.id)
    }
}
