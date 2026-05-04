//
//  SmartBoardEditorView.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/04/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct SmartBoardDefinition: Identifiable, Codable, Hashable, Transferable {
    var id: String = UUID().uuidString
    var name: String
    var discussionPath: String = ""
    var subjectContains: String = ""
    var replyContains: String = ""
    var nickContains: String = ""
    var unreadOnly: Bool = false

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { item in
            "smartboard:" + item.id
        } importing: { string in
            guard string.hasPrefix("smartboard:") else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a smart board drag"))
            }
            let id = String(string.dropFirst("smartboard:".count))
            return SmartBoardDefinition(id: id, name: "")
        }
    }
}

struct SmartBoardEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialValue: SmartBoardDefinition?
    let discussionOptions: [String]
    let onSave: (SmartBoardDefinition) -> Void

    @State private var name: String
    @State private var discussionPath: String
    @State private var subjectContains: String
    @State private var replyContains: String
    @State private var nickContains: String
    @State private var unreadOnly: Bool

    init(
        initialValue: SmartBoardDefinition?,
        discussionOptions: [String],
        onSave: @escaping (SmartBoardDefinition) -> Void
    ) {
        self.initialValue = initialValue
        self.discussionOptions = discussionOptions.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        self.onSave = onSave

        _name = State(initialValue: initialValue?.name ?? "")
        _discussionPath = State(initialValue: initialValue?.discussionPath ?? "")
        _subjectContains = State(initialValue: initialValue?.subjectContains ?? "")
        _replyContains = State(initialValue: initialValue?.replyContains ?? "")
        _nickContains = State(initialValue: initialValue?.nickContains ?? "")
        _unreadOnly = State(initialValue: initialValue?.unreadOnly ?? false)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: String {
        initialValue == nil ? NSLocalizedString("New Smart Board", comment: "") : NSLocalizedString("Edit Smart Board", comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            HStack {
                Text("Name:")
                    .frame(width: 90, alignment: .trailing)
                TextField("Unread", text: $name)
            }

            GroupBox("Thread Filters") {
                VStack(spacing: 10) {
                    HStack {
                        Text("Board:")
                            .frame(width: 90, alignment: .trailing)
                        Picker("", selection: $discussionPath) {
                            Text("All Boards").tag("")
                            ForEach(discussionOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Subject:")
                            .frame(width: 90, alignment: .trailing)
                        TextField("", text: $subjectContains)
                    }

                    HStack {
                        Text("Reply:")
                            .frame(width: 90, alignment: .trailing)
                        TextField("", text: $replyContains)
                    }

                    HStack {
                        Text("Nick:")
                            .frame(width: 90, alignment: .trailing)
                        TextField("", text: $nickContains)
                    }

                    HStack(spacing: 8) {
                        Text("Unread:")
                            .frame(width: 90, alignment: .trailing)
                        Toggle("Yes", isOn: $unreadOnly)
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    let value = SmartBoardDefinition(
                        id: initialValue?.id ?? UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        discussionPath: discussionPath,
                        subjectContains: subjectContains,
                        replyContains: replyContains,
                        nickContains: nickContains,
                        unreadOnly: unreadOnly
                    )
                    onSave(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
