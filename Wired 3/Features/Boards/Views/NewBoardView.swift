//
//  NewBoardView.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/04/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct NewBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let parentBoard: Board?

    @State private var boardName: String = ""
    @State private var ownerSelection: String = ""
    @State private var groupSelection: String = ""
    @State private var ownerLevel: PermissionLevel = .readWrite
    @State private var groupLevel: PermissionLevel = .none
    @State private var everyoneLevel: PermissionLevel = .readWrite
    @State private var ownerNames: [String] = []
    @State private var groupNames: [String] = []
    @State private var isLoadingAccounts = false
    @State private var isCreating: Bool = false

    private var parentPathLabel: String {
        parentBoard?.path ?? "/"
    }

    private var resolvedPath: String {
        let trimmedName = boardName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parentPath = (parentBoard?.path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmedName.isEmpty else { return "" }
        guard !parentPath.isEmpty else { return trimmedName }
        return "\(parentPath)/\(trimmedName)"
    }

    private var canCreate: Bool {
        !resolvedPath.isEmpty &&
        runtime.hasPrivilege("wired.account.board.add_boards") &&
        !isCreating
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
                Text("New Board")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Location") {
                    LabeledContent("Parent", value: parentPathLabel)
                    TextField("Board Name", text: $boardName)
                    if !resolvedPath.isEmpty {
                        LabeledContent("Path", value: resolvedPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Permissions") {
                    Picker("Owner", selection: $ownerSelection) {
                        Text("None").tag("")
                        ForEach(ownerOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoadingAccounts)

                    Picker("Owner access", selection: $ownerLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }

                    Picker("Group", selection: $groupSelection) {
                        Text("None").tag("")
                        ForEach(groupOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoadingAccounts)

                    Picker("Group access", selection: $groupLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }

                    Picker("Everyone", selection: $everyoneLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .overlay {
                if isLoadingAccounts {
                    ProgressView("Loading accounts…")
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create") { createBoard() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .task {
            await loadAccounts()
        }
    }

    private func createBoard() {
        isCreating = true
        Task {
            do {
                try await runtime.addBoard(
                    path: resolvedPath,
                    owner: ownerSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerRead: ownerLevel.read,
                    ownerWrite: ownerLevel.write,
                    group: groupSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    groupRead: groupLevel.read,
                    groupWrite: groupLevel.write,
                    everyoneRead: everyoneLevel.read,
                    everyoneWrite: everyoneLevel.write
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isCreating = false
                }
            }
        }
    }

    @MainActor
    private func loadAccounts() async {
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }

        do {
            async let users = runtime.listAccountUserNames()
            async let groups = runtime.listAccountGroupNames()
            ownerNames = try await users
            groupNames = try await groups
        } catch {
            runtime.lastError = error
        }
    }
}
