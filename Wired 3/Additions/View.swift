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
                    buttonTitle: String = "OK",
                    dismiss: (() -> Void)? = nil) -> some View {
        
        // Binding Bool réactif pour contrôler l'alerte
        let isPresented = Binding<Bool>(
            get: { error.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    error.wrappedValue = nil
                    dismiss?()
                }
            }
        )
        
        // On prépare un "presenting" non optionnel pour la closure de la nouvelle API
        // (la closure recevra l'erreur non-optional si elle existe)
        let presentingError = error.wrappedValue
        
        // Titre / message extraits de l'erreur
        var errorTitle = String(localized: "Unknown error")
        var errorMessage = ""
        if let appError = presentingError as? WiredError {
            errorTitle = appError.title
            errorMessage = appError.message
        }
        else if let networkError = presentingError as? WiredSwift.NetworkError {
            errorTitle = "Network Error"
            errorMessage = networkError.localizedDescription
        }
        else if let asyncConnectionError = presentingError as? AsyncConnectionError {
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
        }
        else if let e = presentingError {
            errorMessage = e.localizedDescription
        }
        
        if errorMessage.isEmpty { errorMessage = "No error message" }

        // Nouvelle API iOS 17+: alert(_:isPresented:presenting:actions:message:)
        return alert(errorTitle,
                     isPresented: isPresented,
                     presenting: presentingError) { _ in
            Button(buttonTitle, role: .cancel) {
                // Le bouton ferme via isPresented binding automatiquement,
                // mais on peut faire un callback si besoin.
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("OKErrorButton")
        } message: { presenting in
            // presenting est non-optional ici (la valeur passée)
            Text(errorMessage)
        }
    }
}
