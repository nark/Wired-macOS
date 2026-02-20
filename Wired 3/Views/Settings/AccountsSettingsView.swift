import SwiftUI
import WiredSwift

private func accountPrivilegesIncludingColorFromSpec() -> [String] {
    var privileges = spec?.accountPrivileges ?? []

    if spec?.fieldsByName["wired.account.color"] != nil,
       !privileges.contains("wired.account.color") {
        privileges.append("wired.account.color")
    }

    return privileges
}

enum AccountFilter: String, CaseIterable, Identifiable {
    case all
    case users
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tous"
        case .users: return "Utilisateurs"
        case .groups: return "Groupes"
        }
    }
}

enum AccountDetailTab: String, CaseIterable, Identifiable {
    case account
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Compte"
        case .permissions: return "Permissions"
        }
    }
}

enum AccountType: String {
    case user
    case group
}

struct AccountSummary: Identifiable, Hashable {
    var id: String { "\(type.rawValue):\(name)" }

    let type: AccountType
    let name: String
    let fullName: String
    let comment: String
    let creationTime: Date?
    let modificationTime: Date?
    let loginTime: Date?
    let editedBy: String
    let downloads: UInt32
    let uploads: UInt32
    let downloadTransferred: UInt64
    let uploadTransferred: UInt64
    let color: UInt32
}

struct AccountEditor {
    var type: AccountType
    var originalName: String
    var name: String
    var fullName: String
    var comment: String
    var password: String
    var primaryGroup: String
    var secondaryGroups: [String]
    var editedBy: String
    var creationTime: Date?
    var modificationTime: Date?
    var loginTime: Date?
    var downloads: UInt32
    var uploads: UInt32
    var downloadTransferred: UInt64
    var uploadTransferred: UInt64
    var privilegesBool: [String: Bool]
    var privilegesUInt32: [String: UInt32]

    var secondaryGroupsString: String {
        get { secondaryGroups.joined(separator: ", ") }
        set {
            secondaryGroups = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}

@MainActor
final class AccountsSettingsViewModel: ObservableObject {
    @Published var users: [AccountSummary] = []
    @Published var groups: [AccountSummary] = []
    @Published var selectedID: String?
    @Published var selectedFilter: AccountFilter = .all
    @Published var selectedDetailTab: AccountDetailTab = .account
    @Published var searchText: String = ""
    @Published var editor: AccountEditor?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: Error?

    private weak var runtime: ConnectionRuntime?
    private var isSubscribedToAccountChanges = false

    func configure(runtime: ConnectionRuntime) {
        self.runtime = runtime
    }

    func subscribeToAccountChangesIfNeeded() async {
        guard !isSubscribedToAccountChanges else { return }
        guard canListAccounts else { return }
        guard let connection = runtime?.connection as? AsyncConnection else { return }

        let message = P7Message(withName: "wired.account.subscribe_accounts", spec: spec!)

        do {
            let response = try await connection.sendAsync(message)
            if let response, response.name == "wired.error" {
                let errorName = response.string(forField: "wired.error.string") ?? ""
                if errorName == "wired.error.already_subscribed" {
                    isSubscribedToAccountChanges = true
                    return
                }
                throw WiredError(message: response)
            }

            isSubscribedToAccountChanges = true
        } catch {
            self.error = error
        }
    }

    func unsubscribeFromAccountChangesIfNeeded() async {
        guard isSubscribedToAccountChanges else { return }
        guard let connection = runtime?.connection as? AsyncConnection else { return }

        let message = P7Message(withName: "wired.account.unsubscribe_accounts", spec: spec!)

        do {
            let response = try await connection.sendAsync(message)
            if let response, response.name == "wired.error" {
                let errorName = response.string(forField: "wired.error.string") ?? ""
                if errorName == "wired.error.not_subscribed" {
                    isSubscribedToAccountChanges = false
                    return
                }
                throw WiredError(message: response)
            }

            isSubscribedToAccountChanges = false
        } catch {
            self.error = error
        }
    }

    var canListAccounts: Bool {
        runtime?.hasPrivilege("wired.account.account.list_accounts") ?? false
    }

    var canReadAccounts: Bool {
        runtime?.hasPrivilege("wired.account.account.read_accounts") ?? false
    }

    var canEditUsers: Bool {
        runtime?.hasPrivilege("wired.account.account.edit_users") ?? false
    }

    var canEditGroups: Bool {
        runtime?.hasPrivilege("wired.account.account.edit_groups") ?? false
    }

    var filteredAccounts: [AccountSummary] {
        let source: [AccountSummary]

        switch selectedFilter {
        case .all:
            source = users + groups
        case .users:
            source = users
        case .groups:
            source = groups
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sortedAccounts(source)
        }

        return source
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) || $0.fullName.localizedCaseInsensitiveContains(trimmed) }
            .sorted(by: accountComparator)
    }

    private func sortedAccounts(_ source: [AccountSummary]) -> [AccountSummary] {
        source.sorted(by: accountComparator)
    }

    private func accountComparator(_ lhs: AccountSummary, _ rhs: AccountSummary) -> Bool {
        if selectedFilter == .all, lhs.type != rhs.type {
            return lhs.type == .user
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    func loadAccountsIfNeeded() async {
        guard users.isEmpty, groups.isEmpty else { return }
        await reloadAccounts()
    }

    func reloadAccounts() async {
        guard let connection = runtime?.connection as? AsyncConnection else { return }
        guard canListAccounts else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedUsers = loadUsers(connection: connection)
            async let loadedGroups = loadGroups(connection: connection)

            users = try await loadedUsers
            groups = try await loadedGroups

            let allIDs = Set((users + groups).map(\.id))
            if let selectedID, !allIDs.contains(selectedID) {
                self.selectedID = nil
                self.editor = nil
            }

            if self.selectedID == nil {
                self.selectedID = filteredAccounts.first?.id
            }

            await readSelectedAccountIfNeeded()
        } catch {
            self.error = error
        }
    }

    func readSelectedAccountIfNeeded() async {
        guard let selected = filteredAccounts.first(where: { $0.id == selectedID }) else {
            editor = nil
            return
        }

        guard let connection = runtime?.connection as? AsyncConnection else { return }
        guard canReadAccounts else { return }

        do {
            switch selected.type {
            case .user:
                editor = try await readUser(name: selected.name, connection: connection)
            case .group:
                editor = try await readGroup(name: selected.name, connection: connection)
            }
        } catch {
            self.error = error
        }
    }

    func saveSelectedAccount() async {
        guard let editor else { return }
        guard let connection = runtime?.connection as? AsyncConnection else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            switch editor.type {
            case .user:
                guard canEditUsers else { return }
                try await editUser(editor, connection: connection)
            case .group:
                guard canEditGroups else { return }
                try await editGroup(editor, connection: connection)
            }

            await reloadAccounts()
            selectedID = "\(editor.type.rawValue):\(editor.name)"
            await readSelectedAccountIfNeeded()
        } catch {
            self.error = error
        }
    }

    func togglePermission(_ key: String, enabled: Bool) {
        guard var editor else { return }
        editor.privilegesBool[key] = enabled
        self.editor = editor
    }

    func setPermission(_ key: String, value: UInt32) {
        guard var editor else { return }
        editor.privilegesUInt32[key] = value
        self.editor = editor
    }

    private func loadUsers(connection: AsyncConnection) async throws -> [AccountSummary] {
        let message = P7Message(withName: "wired.account.list_users", spec: spec!)

        var values: [AccountSummary] = []

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.user_list" {
                values.append(parseUserSummary(message: response))
            }
        }

        return values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func loadGroups(connection: AsyncConnection) async throws -> [AccountSummary] {
        let message = P7Message(withName: "wired.account.list_groups", spec: spec!)

        var values: [AccountSummary] = []

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.group_list" {
                values.append(parseGroupSummary(message: response))
            }
        }

        return values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func readUser(name: String, connection: AsyncConnection) async throws -> AccountEditor {
        let message = P7Message(withName: "wired.account.read_user", spec: spec!)
        message.addParameter(field: "wired.account.name", value: name)

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.user" {
                return parseUserEditor(message: response)
            }
        }

        throw NSError(domain: "Wired3.Accounts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aucune réponse wired.account.user reçue"])
    }

    private func readGroup(name: String, connection: AsyncConnection) async throws -> AccountEditor {
        let message = P7Message(withName: "wired.account.read_group", spec: spec!)
        message.addParameter(field: "wired.account.name", value: name)

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.group" {
                return parseGroupEditor(message: response)
            }
        }

        throw NSError(domain: "Wired3.Accounts", code: 2, userInfo: [NSLocalizedDescriptionKey: "Aucune réponse wired.account.group reçue"])
    }

    private func editUser(_ editor: AccountEditor, connection: AsyncConnection) async throws {
        let message = P7Message(withName: "wired.account.edit_user", spec: spec!)
        message.addParameter(field: "wired.account.name", value: editor.originalName)

        if editor.name != editor.originalName {
            message.addParameter(field: "wired.account.new_name", value: editor.name)
        }

        message.addParameter(field: "wired.account.full_name", value: editor.fullName)
        message.addParameter(field: "wired.account.comment", value: editor.comment)
        message.addParameter(field: "wired.account.group", value: editor.primaryGroup)
        message.addParameter(field: "wired.account.groups", value: editor.secondaryGroups)
        message.addParameter(field: "wired.account.password", value: editor.password)

        for privilege in accountPrivilegesIncludingColorFromSpec() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                message.addParameter(field: privilege, value: editor.privilegesBool[privilege] ?? false)
            case .enum32, .uint32:
                message.addParameter(field: privilege, value: editor.privilegesUInt32[privilege] ?? 0)
            default:
                break
            }
        }

        let response = try await connection.sendAsync(message)

        if let response, response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    private func editGroup(_ editor: AccountEditor, connection: AsyncConnection) async throws {
        let message = P7Message(withName: "wired.account.edit_group", spec: spec!)
        message.addParameter(field: "wired.account.name", value: editor.originalName)

        if editor.name != editor.originalName {
            message.addParameter(field: "wired.account.new_name", value: editor.name)
        }

        message.addParameter(field: "wired.account.comment", value: editor.comment)

        for privilege in accountPrivilegesIncludingColorFromSpec() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                message.addParameter(field: privilege, value: editor.privilegesBool[privilege] ?? false)
            case .enum32, .uint32:
                message.addParameter(field: privilege, value: editor.privilegesUInt32[privilege] ?? 0)
            default:
                break
            }
        }

        let response = try await connection.sendAsync(message)

        if let response, response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    private func parseUserSummary(message: P7Message) -> AccountSummary {
        AccountSummary(
            type: .user,
            name: message.string(forField: "wired.account.name") ?? "",
            fullName: message.string(forField: "wired.account.full_name") ?? "",
            comment: message.string(forField: "wired.account.comment") ?? "",
            creationTime: message.date(forField: "wired.account.creation_time"),
            modificationTime: message.date(forField: "wired.account.modification_time"),
            loginTime: message.date(forField: "wired.account.login_time"),
            editedBy: message.string(forField: "wired.account.edited_by") ?? "",
            downloads: message.uint32(forField: "wired.account.downloads") ?? 0,
            uploads: message.uint32(forField: "wired.account.uploads") ?? 0,
            downloadTransferred: message.uint64(forField: "wired.account.download_transferred") ?? 0,
            uploadTransferred: message.uint64(forField: "wired.account.upload_transferred") ?? 0,
            color: message.enumeration(forField: "wired.account.color")
                ?? message.uint32(forField: "wired.account.color")
                ?? 0
        )
    }

    private func parseGroupSummary(message: P7Message) -> AccountSummary {
        AccountSummary(
            type: .group,
            name: message.string(forField: "wired.account.name") ?? "",
            fullName: "",
            comment: message.string(forField: "wired.account.comment") ?? "",
            creationTime: message.date(forField: "wired.account.creation_time"),
            modificationTime: message.date(forField: "wired.account.modification_time"),
            loginTime: nil,
            editedBy: message.string(forField: "wired.account.edited_by") ?? "",
            downloads: 0,
            uploads: 0,
            downloadTransferred: 0,
            uploadTransferred: 0,
            color: message.enumeration(forField: "wired.account.color")
                ?? message.uint32(forField: "wired.account.color")
                ?? 0
        )
    }

    private func parseUserEditor(message: P7Message) -> AccountEditor {
        var privilegesBool: [String: Bool] = [:]
        var privilegesUInt32: [String: UInt32] = [:]

        for privilege in accountPrivilegesIncludingColorFromSpec() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                privilegesBool[privilege] = message.bool(forField: privilege) ?? false
            case .enum32, .uint32:
                privilegesUInt32[privilege] = message.uint32(forField: privilege) ?? 0
            default:
                break
            }
        }

        return AccountEditor(
            type: .user,
            originalName: message.string(forField: "wired.account.name") ?? "",
            name: message.string(forField: "wired.account.name") ?? "",
            fullName: message.string(forField: "wired.account.full_name") ?? "",
            comment: message.string(forField: "wired.account.comment") ?? "",
            password: message.string(forField: "wired.account.password") ?? "",
            primaryGroup: message.string(forField: "wired.account.group") ?? "",
            secondaryGroups: message.stringList(forField: "wired.account.groups") ?? [],
            editedBy: message.string(forField: "wired.account.edited_by") ?? "",
            creationTime: message.date(forField: "wired.account.creation_time"),
            modificationTime: message.date(forField: "wired.account.modification_time"),
            loginTime: message.date(forField: "wired.account.login_time"),
            downloads: message.uint32(forField: "wired.account.downloads") ?? 0,
            uploads: message.uint32(forField: "wired.account.uploads") ?? 0,
            downloadTransferred: message.uint64(forField: "wired.account.download_transferred") ?? 0,
            uploadTransferred: message.uint64(forField: "wired.account.upload_transferred") ?? 0,
            privilegesBool: privilegesBool,
            privilegesUInt32: privilegesUInt32
        )
    }

    private func parseGroupEditor(message: P7Message) -> AccountEditor {
        var privilegesBool: [String: Bool] = [:]
        var privilegesUInt32: [String: UInt32] = [:]

        for privilege in accountPrivilegesIncludingColorFromSpec() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                privilegesBool[privilege] = message.bool(forField: privilege) ?? false
            case .enum32, .uint32:
                privilegesUInt32[privilege] = message.uint32(forField: privilege) ?? 0
            default:
                break
            }
        }

        return AccountEditor(
            type: .group,
            originalName: message.string(forField: "wired.account.name") ?? "",
            name: message.string(forField: "wired.account.name") ?? "",
            fullName: "",
            comment: message.string(forField: "wired.account.comment") ?? "",
            password: "",
            primaryGroup: "",
            secondaryGroups: [],
            editedBy: message.string(forField: "wired.account.edited_by") ?? "",
            creationTime: message.date(forField: "wired.account.creation_time"),
            modificationTime: message.date(forField: "wired.account.modification_time"),
            loginTime: nil,
            downloads: 0,
            uploads: 0,
            downloadTransferred: 0,
            uploadTransferred: 0,
            privilegesBool: privilegesBool,
            privilegesUInt32: privilegesUInt32
        )
    }
}

struct AccountsSettingsView: View {
    @StateObject private var viewModel = AccountsSettingsViewModel()

    let runtime: ConnectionRuntime

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                Picker("Type", selection: $viewModel.selectedFilter) {
                    ForEach(AccountFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                List(selection: $viewModel.selectedID) {
                    ForEach(viewModel.filteredAccounts) { account in
                        HStack(spacing: 6) {
                            Image(systemName: account.type == .group ? "person.3" : "person")
                            if account.name == "admin" {
                                Text(account.name)
                                    .fontWeight(.bold)
                                    .foregroundStyle(accountSummaryColor(account.color))
                            } else {
                                Text(account.name)
                                    .foregroundStyle(accountSummaryColor(account.color))
                            }
                        }
                        .tag(account.id)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Button {
                        Task { await viewModel.reloadAccounts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Recharger")

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260)
        } detail: {
            detailView
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task {
            viewModel.configure(runtime: runtime)
            await viewModel.loadAccountsIfNeeded()
            await viewModel.subscribeToAccountChangesIfNeeded()
        }
        .onDisappear {
            Task {
                await viewModel.unsubscribeFromAccountChangesIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiredAccountAccountsChanged)) { notification in
            guard let runtimeID = notification.userInfo?["runtimeID"] as? UUID else { return }
            guard runtimeID == runtime.id else { return }

            Task {
                await viewModel.reloadAccounts()
            }
        }
        .onChange(of: viewModel.selectedID) { _, _ in
            Task { await viewModel.readSelectedAccountIfNeeded() }
        }
        .errorAlert(error: Binding(
            get: { viewModel.error },
            set: { viewModel.error = $0 }
        ))
    }

    @ViewBuilder
    private var detailView: some View {
        if !viewModel.canListAccounts {
            ContentUnavailableView("Accès refusé", systemImage: "lock", description: Text("Permission requise: wired.account.account.list_accounts"))
        } else if viewModel.filteredAccounts.isEmpty {
            ContentUnavailableView("Aucun compte", systemImage: "person.2")
        } else if let editor = viewModel.editor {
            VStack(spacing: 12) {
                Picker("", selection: $viewModel.selectedDetailTab) {
                    ForEach(AccountDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .padding(.top, 14)

                switch viewModel.selectedDetailTab {
                case .account:
                    AccountEditorForm(editor: editor) { updated in
                        viewModel.editor = updated
                    }
                case .permissions:
                    AccountPermissionsForm(
                        editor: editor,
                        onToggle: { key, value in
                            viewModel.togglePermission(key, enabled: value)
                        },
                        onSetUInt32: { key, value in
                            viewModel.setPermission(key, value: value)
                        }
                    )
                }

                HStack {
                    Spacer()
                    Button("Sauvegarder") {
                        Task { await viewModel.saveSelectedAccount() }
                    }
                    .disabled(!canSave(editor: editor))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        } else {
            ContentUnavailableView("Sélectionne un compte", systemImage: "person.crop.square")
        }
    }

    private func canSave(editor: AccountEditor) -> Bool {
        if viewModel.isSaving {
            return false
        }

        switch editor.type {
        case .user:
            return viewModel.canEditUsers
        case .group:
            return viewModel.canEditGroups
        }
    }
}

private struct AccountEditorForm: View {
    let editor: AccountEditor
    let onUpdate: (AccountEditor) -> Void

    private let formatter = ByteCountFormatter()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                GroupBox {
                    VStack(spacing: 10) {
                        row(label: "Type") {
                            Text(editor.type == .group ? "Groupe" : "Utilisateur")
                                .foregroundStyle(.secondary)
                        }

                        editableRow(label: "Nom", text: editor.name) { value in
                            var copy = editor
                            copy.name = value
                            onUpdate(copy)
                        }

                        editableRow(label: "Nom complet", text: editor.fullName) { value in
                            var copy = editor
                            copy.fullName = value
                            onUpdate(copy)
                        }

                        if editor.type == .user {
                            editableSecureRow(label: "Mot de passe", text: editor.password) { value in
                                var copy = editor
                                copy.password = value
                                onUpdate(copy)
                            }

                            editableRow(label: "Groupe primaire", text: editor.primaryGroup) { value in
                                var copy = editor
                                copy.primaryGroup = value
                                onUpdate(copy)
                            }

                            editableRow(label: "Groupes secondaires", text: editor.secondaryGroupsString) { value in
                                var copy = editor
                                copy.secondaryGroupsString = value
                                onUpdate(copy)
                            }
                        }

                        editableMultilineRow(label: "Commentaire", text: editor.comment) { value in
                            var copy = editor
                            copy.comment = value
                            onUpdate(copy)
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        dateLine("Création", value: editor.creationTime)
                        dateLine("Modification", value: editor.modificationTime)
                        dateLine("Dernière connexion", value: editor.loginTime)
                        line("Modifié par", value: editor.editedBy)
                        line("Téléchargements", value: "\(editor.downloads) terminé, \(formatBytes(editor.downloadTransferred)) transféré")
                        line("Téléversements", value: "\(editor.uploads) terminé, \(formatBytes(editor.uploadTransferred)) transféré")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editableRow(label: String, text: String, onChange: @escaping (String) -> Void) -> some View {
        row(label: label) {
            TextField("", text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func editableSecureRow(label: String, text: String, onChange: @escaping (String) -> Void) -> some View {
        row(label: label) {
            SecureField("", text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func editableMultilineRow(label: String, text: String, onChange: @escaping (String) -> Void) -> some View {
        row(label: label) {
            TextEditor(text: Binding(get: { text }, set: onChange))
                .frame(minHeight: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )
        }
    }

    private func line(_ label: String, value: String) -> some View {
        HStack {
            Text("\(label):")
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func dateLine(_ label: String, value: Date?) -> some View {
        line(label, value: value.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "-")
    }

    private func formatBytes(_ value: UInt64) -> String {
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }
}

private struct AccountPermissionsForm: View {
    let editor: AccountEditor
    let onToggle: (String, Bool) -> Void
    let onSetUInt32: (String, UInt32) -> Void

    private var groupedPrivileges: [(PermissionCategory, [String])] {
        var buckets: [PermissionCategory: [String]] = [:]

        for key in accountPrivilegesIncludingColorFromSpec() {
            guard let field = spec?.fieldsByName[key] else { continue }
            guard field.type == .bool || field.type == .enum32 || field.type == .uint32 else { continue }

            let category = PermissionCategory.category(for: key)
            buckets[category, default: []].append(key)
        }

        var result: [(PermissionCategory, [String])] = []

        for category in PermissionCategory.displayOrder {
            let keys = (buckets[category] ?? []).sorted(by: permissionSortKey)
            if !keys.isEmpty {
                result.append((category, keys))
            }
        }

        return result
    }

    private func permissionSortKey(_ lhs: String, _ rhs: String) -> Bool {
        permissionDisplayName(lhs).localizedCaseInsensitiveCompare(permissionDisplayName(rhs)) == .orderedAscending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Permissions")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            List {
                ForEach(groupedPrivileges, id: \.0) { category, keys in
                    Section(category.title) {
                        ForEach(keys, id: \.self) { key in
                            if spec?.fieldsByName[key]?.type == .bool {
                                Toggle(isOn: Binding(
                                    get: { editor.privilegesBool[key] ?? false },
                                    set: { onToggle(key, $0) }
                                )) {
                                    Text(permissionDisplayName(key))
                                        .font(.system(size: 12))
                                }
                            } else {
                                HStack {
                                    Text(permissionDisplayName(key))
                                        .font(.system(size: 12))
                                    Spacer()

                                    if key == "wired.account.color" {
                                        Picker(
                                            "",
                                            selection: Binding(
                                                get: { editor.privilegesUInt32[key] ?? 0 },
                                                set: { onSetUInt32(key, $0) }
                                            )
                                        ) {
                                            ForEach(WiredAccountColor.allCases) { option in
                                                HStack(spacing: 8) {
                                                    Circle()
                                                        .fill(option.color)
                                                        .frame(width: 10, height: 10)
                                                    Text(option.title)
                                                }
                                                .tag(option.rawValue)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .frame(width: 150, alignment: .trailing)
                                    } else {
                                        TextField(
                                            "",
                                            value: Binding(
                                                get: { editor.privilegesUInt32[key] ?? 0 },
                                                set: { onSetUInt32(key, $0) }
                                            ),
                                            format: .number
                                        )
                                        .frame(width: 90)
                                        .multilineTextAlignment(.trailing)
                                        .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private enum PermissionCategory: String, CaseIterable, Hashable {
    case basic
    case files
    case messages
    case transfers
    case boards
    case users
    case accounts
    case administration
    case tracker
    case limits
    case other

    static var displayOrder: [PermissionCategory] {
        [.basic, .files, .messages, .transfers, .boards, .users, .accounts, .administration, .tracker, .limits, .other]
    }

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .files: return "Files"
        case .messages: return "Messages"
        case .transfers: return "Transfers"
        case .boards: return "Boards"
        case .users: return "Users"
        case .accounts: return "Accounts"
        case .administration: return "Administration"
        case .tracker: return "Tracker"
        case .limits: return "Limits"
        case .other: return "Other"
        }
    }

    static func category(for key: String) -> PermissionCategory {
        if key == "wired.account.color" ||
            key.hasPrefix("wired.account.chat.create_") ||
            key == "wired.account.chat.set_topic" ||
            key == "wired.account.user.cannot_set_nick" ||
            key == "wired.account.user.get_info" {
            return .basic
        }

        if key.hasPrefix("wired.account.message.") {
            return .messages
        }

        if key.hasPrefix("wired.account.transfer.") {
            if key.hasSuffix("_limit") || key.hasSuffix("_speed_limit") {
                return .limits
            }
            return .transfers
        }

        if key == "wired.account.files" || key.hasPrefix("wired.account.file.") {
            if key.hasSuffix("_limit") {
                return .limits
            }
            return .files
        }

        if key.hasPrefix("wired.account.board.") {
            return .boards
        }

        if key.hasPrefix("wired.account.tracker.") {
            return .tracker
        }

        if key == "wired.account.chat.kick_users" ||
            key == "wired.account.user.disconnect_users" ||
            key == "wired.account.user.ban_users" ||
            key == "wired.account.user.cannot_be_disconnected" ||
            key == "wired.account.user.get_users" {
            return .users
        }

        if key.hasPrefix("wired.account.account.") {
            return .accounts
        }

        if key.hasPrefix("wired.account.log.") ||
            key.hasPrefix("wired.account.events.") ||
            key.hasPrefix("wired.account.settings.") ||
            key.hasPrefix("wired.account.banlist.") {
            return .administration
        }

        if key.hasSuffix("_limit") {
            return .limits
        }

        return .other
    }
}

private func permissionDisplayName(_ key: String) -> String {
    if key == "wired.account.color" {
        return "Color"
    }

    let short = key.replacingOccurrences(of: "wired.account.", with: "")
    let words = short
        .split(separator: ".")
        .joined(separator: " ")
        .split(separator: "_")
        .map { $0.capitalized }

    return words.joined(separator: " ")
}

private enum WiredAccountColor: UInt32, CaseIterable, Identifiable {
    case black = 0
    case red = 1
    case orange = 2
    case green = 3
    case blue = 4
    case purple = 5

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .black: return "Black"
        case .red: return "Red"
        case .orange: return "Orange"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    var color: Color {
        switch self {
        case .black: return .black
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }
}

private func accountSummaryColor(_ value: UInt32) -> Color {
    WiredAccountColor(rawValue: value)?.color ?? .primary
}
