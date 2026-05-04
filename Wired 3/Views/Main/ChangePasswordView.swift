//
//  ChangePasswordView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import KeychainSwift
import WiredSwift

struct ChangePasswordView: View {
    let connectionID: UUID
    /// When `true`, the sheet was opened because the account has a legacy SHA1 password
    /// (migrated from Wired 2.5). The Cancel button is hidden and an informational banner
    /// is shown to explain why a new password is required.
    var isMandatory: Bool = false

    @Environment(ConnectionController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if isMandatory {
                    Section {
                        Label {
                            Text("Your account was migrated from Wired 2.5. You must set a new password before you can use this server.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    SecureField("New password", text: $newPassword)
                    SecureField("Confirm password", text: $confirmPassword)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                if !isMandatory {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                Button("Change") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isLoading)
            }
            .padding(12)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(isMandatory)
    }

    private func submit() async {
        guard let runtime = controller.runtime(for: connectionID),
              let connection = runtime.connection as? AsyncConnection else {
            errorMessage = NSLocalizedString("No active connection.", comment: "")
            return
        }

        isLoading = true
        errorMessage = nil

        let hashed = newPassword.sha256()
        let message = P7Message(withName: "wired.account.change_password", spec: spec)
        message.addParameter(field: "wired.account.password", value: hashed)

        do {
            let response = try await connection.sendAsync(message)
            if let response, response.name == "wired.error" {
                errorMessage = response.string(forField: "wired.error.string") ?? NSLocalizedString("Server error.", comment: "")
                isLoading = false
                return
            }

            // Update keychain so the next bookmark reconnect uses the new password.
            if let config = controller.configuration(for: connectionID) {
                KeychainSwift().set(newPassword, forKey: "\(config.login)@\(config.hostname)")
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
