//
//  View.swift
//  UDM
//
//  Created by Rafaël Warnault on 11/12/2025.
//

import SwiftUI
import WiredSwift

extension View {
    func errorAlert(error: Binding<Error?>,
                    source: String = "Unknown",
                    serverName: String? = nil,
                    connectionID: UUID? = nil,
                    buttonTitle: String = "OK",
                    dismiss: (() -> Void)? = nil) -> some View {
        modifier(
            ErrorAlertModifier(
                error: error,
                source: source,
                serverName: serverName,
                connectionID: connectionID,
                buttonTitle: buttonTitle,
                dismiss: dismiss
            )
        )
    }
}

struct PresentedAppError {
    let title: String
    let message: String
    let details: String
}

struct ErrorToastPayload: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let source: String
    let serverName: String?

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        source: String,
        serverName: String?
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.source = source
        self.serverName = serverName
    }
}

@MainActor
@Observable
final class ErrorToastCenter {
    var activeToast: ErrorToastPayload?
    private var hideToastTask: Task<Void, Never>?

    func present(_ payload: ErrorToastPayload) {
        hideToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            activeToast = payload
        }

        hideToastTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.dismiss()
            }
        }
    }

    func dismiss() {
        hideToastTask?.cancel()
        hideToastTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            activeToast = nil
        }
    }
}

struct ErrorToastOverlay: View {
    @Environment(ErrorToastCenter.self) private var errorToastCenter

    var body: some View {
        if let activeToast = errorToastCenter.activeToast {
            ErrorToastView(
                title: activeToast.title,
                message: activeToast.message,
                source: activeToast.source,
                serverName: activeToast.serverName,
                dismiss: {
                    errorToastCenter.dismiss()
                }
            )
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

func presentableError(from error: Error?) -> PresentedAppError {
    var errorTitle = String(localized: "Unknown error")
    var errorMessage = ""

    if let appError = error as? WiredError {
        errorTitle = appError.title
        errorMessage = appError.message
    } else if let networkError = error as? WiredSwift.NetworkError {
        errorTitle = "Network Error"
        errorMessage = networkError.localizedDescription
    } else if let asyncConnectionError = error as? AsyncConnectionError {
        switch asyncConnectionError {
        case .notConnected:
            errorTitle = "Not Connected"
            errorMessage = "You are not connected to the server"
        case .writeFailed:
            errorTitle = "Write Failed"
            errorMessage = "Write operation failed"
        case .serverError(let message):
            let wiredError = WiredError(message: message)
            errorTitle = wiredError.title
            errorMessage = wiredError.message
        }
    } else if let e = error {
        errorMessage = e.localizedDescription
    }

    if errorMessage.isEmpty {
        errorMessage = "No error message"
    }

    let nsError = error as NSError?
    let details: String
    if let nsError {
        details = "\(nsError.domain) (\(nsError.code)) - \(nsError.localizedDescription)"
    } else {
        details = errorMessage
    }

    return PresentedAppError(title: errorTitle, message: errorMessage, details: details)
}

private struct ErrorAlertModifier: ViewModifier {
    @Environment(ErrorLogStore.self) private var errorLogStore
    @Environment(ErrorToastCenter.self) private var errorToastCenter

    @Binding var error: Error?
    let source: String
    let serverName: String?
    let connectionID: UUID?
    let buttonTitle: String
    let dismiss: (() -> Void)?

    @State private var lastLoggedFingerprint: String?

    func body(content: Content) -> some View {
        _ = buttonTitle
        let presentingError = error
        let presentation = presentableError(from: presentingError)

        return content
            .onChange(of: presentingError == nil) { _, isNil in
                if isNil {
                    lastLoggedFingerprint = nil
                }
            }
            .onChange(of: error != nil) { _, hasError in
                guard hasError, let error = presentingError else { return }
                let fingerprint = "\(source)|\(serverName ?? "")|\((error as NSError).domain)|\((error as NSError).code)|\(presentation.message)"
                guard fingerprint != lastLoggedFingerprint else { return }
                lastLoggedFingerprint = fingerprint
                errorLogStore.record(
                    error: error,
                    source: source,
                    serverName: serverName,
                    connectionID: connectionID
                )
                errorToastCenter.present(
                    ErrorToastPayload(
                        title: presentation.title,
                        message: presentation.message,
                        source: source,
                        serverName: serverName
                    )
                )

                self.error = nil
                dismiss?()
            }
    }
}

struct ErrorToastView: View {
    let title: String
    let message: String
    let source: String
    let serverName: String?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            Text(metaLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(radius: 8, y: 2)
    }

    private var metaLine: String {
        if let serverName, !serverName.isEmpty {
            return "\(source) • \(serverName)"
        }
        return source
    }
}
