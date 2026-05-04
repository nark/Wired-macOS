//
//  BoardPathActionView.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 09/04/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

public struct BoardPathActionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let title: String
    let actionLabel: String
    let initialPath: String
    let submit: (String) async throws -> Void

    @State private var path: String
    @State private var isSubmitting = false

    init(
        title: String,
        actionLabel: String,
        initialPath: String,
        submit: @escaping (String) async throws -> Void
    ) {
        self.title = title
        self.actionLabel = actionLabel
        self.initialPath = initialPath
        self.submit = submit
        self._path = State(initialValue: initialPath)
    }

    private var canSubmit: Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialPath && !isSubmitting
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                TextField("Path", text: $path)
                LabeledContent("Current", value: initialPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(LocalizedStringKey(actionLabel)) { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding()
        }
        .frame(width: 520, height: 220)
    }

    private func apply() {
        isSubmitting = true
        Task {
            do {
                try await submit(path.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSubmitting = false
                }
            }
        }
    }
}
