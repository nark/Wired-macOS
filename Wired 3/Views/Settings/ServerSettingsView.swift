import SwiftUI

private enum ServerSettingsCategory: String, CaseIterable, Identifiable {
    case general
    case monitor
    case events
    case log
    case accounts
    case bans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Réglages"
        case .monitor: return "Moniteur"
        case .events: return "Évènements"
        case .log: return "Log"
        case .accounts: return "Comptes"
        case .bans: return "Banissements"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .monitor: return "gauge.with.dots.needle.50percent"
        case .events: return "flag"
        case .log: return "doc.text"
        case .accounts: return "person.2"
        case .bans: return "minus.circle.fill"
        }
    }
}

struct ServerSettingsView: View {
    @Environment(ConnectionController.self) private var connectionController

    let connectionID: UUID

    @State private var selectedCategory: ServerSettingsCategory? = .accounts

    private var runtime: ConnectionRuntime? {
        connectionController.runtime(for: connectionID)
    }

    var body: some View {
        NavigationSplitView {
            List(ServerSettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.iconName)
                    .tag(category)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory ?? .accounts {
        case .general:
            PlaceholderCategoryView(title: "Réglages")
        case .monitor:
            PlaceholderCategoryView(title: "Moniteur")
        case .events:
            PlaceholderCategoryView(title: "Évènements")
        case .log:
            PlaceholderCategoryView(title: "Log")
        case .accounts:
            if let runtime {
                AccountsSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Comptes")
            }
        case .bans:
            PlaceholderCategoryView(title: "Banissements")
        }
    }
}

private struct PlaceholderCategoryView: View {
    let title: String

    var body: some View {
        VStack {
            Spacer()
            Text(title)
                .font(.title3.weight(.semibold))
            Text("Section en cours d'implémentation")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
