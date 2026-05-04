//
//  EditBoardPermissionsView.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/04/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct EditBoardPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let board: Board

    @State private var ownerSelection: String
    @State private var groupSelection: String
    @State private var ownerLevel: PermissionLevel
    @State private var groupLevel: PermissionLevel
    @State private var everyoneLevel: PermissionLevel
    @State private var ownerNames: [String] = []
    @State private var groupNames: [String] = []
    @State private var isLoading = true
    @State private var isSaving = false

    init(board: Board) {
        self.board = board
        self._ownerSelection = State(initialValue: board.owner)
        self._groupSelection = State(initialValue: board.group)
        self._ownerLevel = State(initialValue: .from(read: board.ownerRead, write: board.ownerWrite))
        self._groupLevel = State(initialValue: .from(read: board.groupRead, write: board.groupWrite))
        self._everyoneLevel = State(initialValue: .from(read: board.everyoneRead, write: board.everyoneWrite))
    }

    private var canSave: Bool {
        runtime.hasPrivilege("wired.account.board.set_board_info") && !isSaving && !isLoading
    }

    private var ownerOptions: [String] {
        var values = ownerNames
        if !ownerSelection.isEmpty && !values.contains(ownerSelection) {
            values.append(ownerSelection)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var groupOptions: [String] {
        var values = groupNames
        if !groupSelection.isEmpty && !values.contains(groupSelection) {
            values.append(groupSelection)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Board Permissions")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Board") {
                    LabeledContent("Path", value: board.path)
                }

                Section("Permissions") {
                    Picker("Owner", selection: $ownerSelection) {
                        Text("None").tag("")
                        ForEach(ownerOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Owner access", selection: $ownerLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Group", selection: $groupSelection) {
                        Text("None").tag("")
                        ForEach(groupOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Group access", selection: $groupLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Everyone", selection: $everyoneLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
            .formStyle(.grouped)
            .overlay {
                if isLoading {
                    ProgressView("Loading permissions…")
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 560, height: 360)
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if runtime.hasPrivilege("wired.account.board.get_board_info") {
            do {
                try await runtime.getBoardInfo(path: board.path)
            } catch {
                runtime.lastError = error
            }
        }

        do {
            async let users = runtime.listAccountUserNames()
            async let groups = runtime.listAccountGroupNames()
            ownerNames = try await users
            groupNames = try await groups
        } catch {
            runtime.lastError = error
        }

        ownerSelection = board.owner
        groupSelection = board.group
        ownerLevel = .from(read: board.ownerRead, write: board.ownerWrite)
        groupLevel = .from(read: board.groupRead, write: board.groupWrite)
        everyoneLevel = .from(read: board.everyoneRead, write: board.everyoneWrite)
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await runtime.setBoardInfo(
                    path: board.path,
                    owner: ownerSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerRead: ownerLevel.read,
                    ownerWrite: ownerLevel.write,
                    group: groupSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    groupRead: groupLevel.read,
                    groupWrite: groupLevel.write,
                    everyoneRead: everyoneLevel.read,
                    everyoneWrite: everyoneLevel.write
                )
                try await runtime.getBoardInfo(path: board.path)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSaving = false
                }
            }
        }
    }
}
