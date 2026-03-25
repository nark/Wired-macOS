import SwiftUI
import WiredSwift
import UniformTypeIdentifiers

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let connectionID: UUID

    @AppStorage("serverSettingsSelectedCategory") private var selectedCategoryRaw: String = ServerSettingsCategory.general.rawValue

    private var selectedCategory: ServerSettingsCategory? {
        ServerSettingsCategory(rawValue: selectedCategoryRaw)
    }

    private var selectedCategoryBinding: Binding<ServerSettingsCategory?> {
        Binding(
            get: { ServerSettingsCategory(rawValue: selectedCategoryRaw) },
            set: { selectedCategoryRaw = $0?.rawValue ?? ServerSettingsCategory.general.rawValue }
        )
    }

    private var runtime: ConnectionRuntime? {
        connectionController.runtime(for: connectionID)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        HSplitView {
            categorySidebar
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)

            detailContent
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
        #else
        if horizontalSizeClass == .compact {
            NavigationStack {
                List(ServerSettingsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        Label(category.title, systemImage: category.iconName)
                    }
                }
                .navigationTitle("Réglages")
                .navigationDestination(for: ServerSettingsCategory.self) { category in
                    detailContent(for: category)
                        .navigationTitle(category.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear {
                            selectedCategoryRaw = category.rawValue
                        }
                }
            }
        } else {
            NavigationSplitView {
                categorySidebar
                    .navigationTitle("Réglages")
            } detail: {
                detailContent
            }
        }
        #endif
    }

    private var categorySidebar: some View {
        List(ServerSettingsCategory.allCases, selection: selectedCategoryBinding) { category in
            Label(category.title, systemImage: category.iconName)
                .tag(category)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        detailContent(for: selectedCategory ?? .general)
    }

    @ViewBuilder
    private func detailContent(for category: ServerSettingsCategory) -> some View {
        switch category {
        case .general:
            if let runtime {
                GeneralServerSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Réglages")
            }
        case .monitor:
            PlaceholderCategoryView(title: "Moniteur")
        case .events:
            if let runtime {
                ServerEventsSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Évènements")
            }
        case .log:
            if let runtime {
                ServerLogSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Log")
            }
        case .accounts:
            if let runtime {
                AccountsSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Comptes")
            }
        case .bans:
            if let runtime {
                BansSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Banissements")
            }
        }
    }
}

private struct GeneralServerSettingsView: View {
    let runtime: ConnectionRuntime

    @State private var serverName: String = ""
    @State private var serverDescription: String = ""
    @State private var bannerData: Data?
    @State private var maxDownloads: Int = 10
    @State private var maxUploads: Int = 10
    @State private var downloadSpeedLimit: Int = 0
    @State private var uploadSpeedLimit: Int = 0
    @State private var registerWithTrackers: Bool = false
    @State private var trackers: [TrackerRow] = [TrackerRow(url: "wired.read-write.fr", login: "guest", password: "", category: "")]
    @State private var selectedTrackerID: UUID?
    @State private var trackerEnabled: Bool = false
    @State private var trackerCategories: [String] = []
    @State private var selectedCategoryIndex: Int?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isApplyingSettings = false
    @State private var isBootstrapping = false
    @State private var didLoadSettings = false
    @State private var permissionDeniedByServer = false
    @State private var lastError: Error?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var bootstrapTask: Task<Void, Never>?
    @State private var isPickingBanner = false

    private var canSetSettings: Bool {
        runtime.hasPrivilege("wired.account.settings.set_settings")
    }

    var body: some View {
        Group {
            if permissionDeniedByServer {
                ContentUnavailableView(
                    "Accès refusé",
                    systemImage: "lock",
                    description: Text("Permission requise: wired.account.settings.get_settings")
                )
            } else if isBootstrapping && !didLoadSettings && !isLoading {
                ContentUnavailableView(
                    "Chargement des réglages",
                    systemImage: "gearshape",
                    description: Text("Récupération des permissions et des paramètres serveur…")
                )
            } else {
                settingsContent
            }
        }
    }

    private var settingsContent: some View {
        settingsPresentationView
    }

    private var settingsPresentationView: some View {
        settingsLifecycleView
            .overlay {
                if isLoading || isSaving {
                    ProgressView()
                }
            }
            .fileImporter(
                isPresented: $isPickingBanner,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                do {
                    let data = try Data(contentsOf: url)
                    bannerData = data
                } catch {
                    lastError = error
                }
            }
            .errorAlert(
                error: $lastError,
                source: "Server Settings",
                serverName: nil,
                connectionID: runtime.id
            )
    }

    private var settingsLifecycleView: some View {
        settingsBaseView
            .task {
                bootstrapTask?.cancel()
                bootstrapTask = Task { await bootstrapLoadSettings() }
            }
            .onChange(of: runtime.joined) { _, joined in
                guard joined else { return }
                guard !didLoadSettings else { return }
                bootstrapTask?.cancel()
                bootstrapTask = Task { await bootstrapLoadSettings() }
            }
            .onChange(of: runtime.userID) { _, userID in
                guard userID > 0 else { return }
                guard !didLoadSettings else { return }
                bootstrapTask?.cancel()
                bootstrapTask = Task { await bootstrapLoadSettings() }
            }
            .onChange(of: runtime.status) { _, status in
                guard status == .connected else { return }
                guard !didLoadSettings else { return }
                bootstrapTask?.cancel()
                bootstrapTask = Task { await bootstrapLoadSettings() }
            }
            .onDisappear {
                autoSaveTask?.cancel()
                autoSaveTask = nil
                bootstrapTask?.cancel()
                bootstrapTask = nil
            }
            .onChange(of: serverName) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: serverDescription) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: maxDownloads) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: maxUploads) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: downloadSpeedLimit) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: uploadSpeedLimit) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: registerWithTrackers) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: trackers) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: trackerEnabled) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: trackerCategories) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: bannerData) { _, _ in
                scheduleAutoSave()
            }
    }

    private var settingsBaseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                basicSettingsSection
                limitsSection

                Divider()

                directorySection
                
                HStack {
                    Button("Recharger") {
                        Task { await loadSettings() }
                    }
                    .disabled(isLoading || isSaving)

                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var basicSettingsSection: some View {
        Group {
            settingsFieldRow("Nom du serveur") {
                TextField("", text: $serverName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canSetSettings)
            }

            settingsFieldRow("Description") {
                TextField("", text: $serverDescription)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canSetSettings)
            }

            settingsFieldRow("Bannière", alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let data = currentBannerData,
                       let bannerImage = Image(data: data) {
                        bannerImage
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 64, alignment: .leading)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary.opacity(0.5))
                            .frame(width: 400, height: 64)
                            .overlay {
                                Text("Taille maximale 400x64")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    Text("Taille maximale 400x64")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if canSetSettings {
                        Button("Choisir une image…") {
                            isPickingBanner = true
                        }
                        .disabled(isSaving || isLoading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var limitsSection: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                settingsNumericRow("Téléchargements simultanés", value: $maxDownloads)
                speedLimitRow("Vit. de téléchargement", value: $downloadSpeedLimit)
            }
            GridRow {
                settingsNumericRow("Téléversements simultanés", value: $maxUploads)
                speedLimitRow("Vit. de téléversement", value: $uploadSpeedLimit)
            }
        }
    }

    private var directorySection: some View {
        settingsFieldRow("", labelWidth: 0, alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                registerWithTrackersToggle

                trackerTable
                trackerToolbar

                Divider()
                    .padding(.vertical, 4)

                trackerEnabledToggle

                settingsFieldRow("Catégories d'annuaire", labelWidth: 0, alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        List(selection: $selectedCategoryIndex) {
                            ForEach(Array(trackerCategories.enumerated()), id: \.offset) { index, value in
                                Text(value)
                                    .tag(index)
                            }
                        }
                        .frame(height: 130)

                        HStack(spacing: 8) {
                            Button {
                                trackerCategories.append("Nouvelle catégorie")
                                selectedCategoryIndex = trackerCategories.count - 1
                            } label: {
                                Image(systemName: "plus")
                            }

                            Button {
                                guard let index = selectedCategoryIndex else { return }
                                guard trackerCategories.indices.contains(index) else { return }
                                trackerCategories.remove(at: index)
                                if trackerCategories.isEmpty {
                                    selectedCategoryIndex = nil
                                } else {
                                    selectedCategoryIndex = min(index, trackerCategories.count - 1)
                                }
                            } label: {
                                Image(systemName: "minus")
                            }
                            .disabled(selectedCategoryIndex == nil)
                        }
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var registerWithTrackersToggle: some View {
        #if os(macOS)
        Toggle("Enregistrer le serveur auprès des annuaires suivants", isOn: $registerWithTrackers)
            .toggleStyle(.checkbox)
        #else
        Toggle("Enregistrer le serveur auprès des annuaires suivants", isOn: $registerWithTrackers)
        #endif
    }

    @ViewBuilder
    private var trackerEnabledToggle: some View {
        #if os(macOS)
        Toggle("Activer l'annuaire", isOn: $trackerEnabled)
            .toggleStyle(.checkbox)
        #else
        Toggle("Activer l'annuaire", isOn: $trackerEnabled)
        #endif
    }

    private var trackerTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                trackerHeader("Adresse", width: 220)
                trackerHeader("Identifiant", width: 130)
                trackerHeader("Mot de passe", width: 130)
                trackerHeader("Catégorie", width: 140)
            }
            .background(.quaternary.opacity(0.35))

            List(selection: $selectedTrackerID) {
                ForEach($trackers) { $tracker in
                    HStack(spacing: 10) {
                        TextField("", text: $tracker.url)
                            .disabled(!canSetSettings)
                        TextField("", text: $tracker.login)
                            .disabled(!canSetSettings)
                        SecureField("", text: $tracker.password)
                            .disabled(!canSetSettings)
                        TextField("", text: $tracker.category)
                            .disabled(!canSetSettings)
                    }
                    .font(.system(size: 12))
                    .tag(tracker.id)
                }
            }
            .listStyle(.plain)
            .frame(height: 100)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var trackerToolbar: some View {
        HStack(spacing: 8) {
            Button {
                trackers.append(TrackerRow(url: "", login: "", password: "", category: ""))
                selectedTrackerID = trackers.last?.id
                scheduleAutoSave()
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!canSetSettings || isSaving)

            Button {
                guard let selectedTrackerID else { return }
                trackers.removeAll { $0.id == selectedTrackerID }
                self.selectedTrackerID = trackers.last?.id
                scheduleAutoSave()
            } label: {
                Image(systemName: "minus")
            }
            .disabled(!canSetSettings || isSaving || selectedTrackerID == nil)
        }
    }

    private func trackerHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private func settingsNumericRow(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text("\(label) :")
                .frame(width: 170, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speedLimitRow(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text("\(label) :")
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            Text("KB/s")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsFieldRow<Content: View>(
        _ label: String,
        labelWidth: CGFloat = 140,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            if labelWidth > 0 {
                Text(label.isEmpty ? " " : "\(label) :")
                    .frame(width: labelWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func loadSettings() async {
        guard let connection = runtime.connection as? AsyncConnection else { return }

        autoSaveTask?.cancel()
        autoSaveTask = nil
        permissionDeniedByServer = false
        isLoading = true
        defer { isLoading = false }

        do {
            let message = P7Message(withName: "wired.settings.get_settings", spec: spec!)
            guard let response = try await connection.sendAsync(message) else { return }

            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            guard response.name == "wired.settings.settings" else { return }
            applySettings(from: response)
            didLoadSettings = true
        } catch {
            if isPermissionDeniedError(error) {
                permissionDeniedByServer = true
                return
            }

            lastError = error
        }
    }

    private func bootstrapLoadSettings() async {
        if didLoadSettings || permissionDeniedByServer {
            return
        }

        isBootstrapping = true
        defer { isBootstrapping = false }

        for _ in 0..<16 {
            guard !Task.isCancelled else { return }

            if let serverInfo = runtime.serverInfo {
                if serverName.isEmpty {
                    serverName = serverInfo.serverName
                }
                if serverDescription.isEmpty {
                    serverDescription = serverInfo.serverDescription
                }
            }

            await loadSettings()

            if didLoadSettings || permissionDeniedByServer {
                return
            }

            try? await Task.sleep(for: .milliseconds(350))
        }

        // Do not block the UI forever if connection/permissions arrive late.
        didLoadSettings = true
    }

    private func saveSettings() async {
        guard let connection = runtime.connection as? AsyncConnection else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let message = P7Message(withName: "wired.settings.set_settings", spec: spec!)
            message.addParameter(field: "wired.info.name", value: serverName)
            message.addParameter(field: "wired.info.description", value: serverDescription)
            message.addParameter(field: "wired.info.downloads", value: UInt32(clamping: maxDownloads))
            message.addParameter(field: "wired.info.uploads", value: UInt32(clamping: maxUploads))
            message.addParameter(field: "wired.info.download_speed", value: UInt32(clamping: max(0, downloadSpeedLimit * 1024)))
            message.addParameter(field: "wired.info.upload_speed", value: UInt32(clamping: max(0, uploadSpeedLimit * 1024)))
            message.addParameter(field: "wired.settings.register_with_trackers", value: registerWithTrackers)
            message.addParameter(
                field: "wired.settings.trackers",
                value: trackers
                    .map { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            message.addParameter(field: "wired.tracker.tracker", value: trackerEnabled)
            message.addParameter(
                field: "wired.tracker.categories",
                value: trackerCategories
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )

            if let bannerData = currentBannerData, !bannerData.isEmpty {
                message.addParameter(field: "wired.info.banner", value: bannerData)
            }

            if let response = try await connection.sendAsync(message), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        } catch {
            lastError = error
        }
    }

    private func applySettings(from message: P7Message) {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        if let value = message.string(forField: "wired.info.name") {
            serverName = value
        }
        if let value = message.string(forField: "wired.info.description") {
            serverDescription = value
        }
        if let value = message.data(forField: "wired.info.banner"), !value.isEmpty {
            bannerData = value
        } else if bannerData == nil, let serverInfo = runtime.serverInfo, !serverInfo.serverBanner.isEmpty {
            bannerData = serverInfo.serverBanner
        }
        if let value = message.uint32(forField: "wired.info.downloads") {
            maxDownloads = Int(value)
        }
        if let value = message.uint32(forField: "wired.info.uploads") {
            maxUploads = Int(value)
        }
        if let value = message.uint32(forField: "wired.info.download_speed") {
            downloadSpeedLimit = Int(value / 1024)
        }
        if let value = message.uint32(forField: "wired.info.upload_speed") {
            uploadSpeedLimit = Int(value / 1024)
        }
        if let value = message.bool(forField: "wired.settings.register_with_trackers") {
            registerWithTrackers = value
        }
        if let value = message.bool(forField: "wired.tracker.tracker") {
            trackerEnabled = value
        }
        if let value = message.stringList(forField: "wired.settings.trackers") {
            trackers = value.map { TrackerRow(url: $0, login: "", password: "", category: "") }
            if trackers.isEmpty {
                trackers = [TrackerRow(url: "", login: "", password: "", category: "")]
            }
            selectedTrackerID = trackers.first?.id
        }
        if let value = message.stringList(forField: "wired.tracker.categories") {
            trackerCategories = value
            selectedCategoryIndex = trackerCategories.isEmpty ? nil : 0
        }
    }

    private var currentBannerData: Data? {
        if let bannerData, !bannerData.isEmpty {
            return bannerData
        }

        if let serverInfo = runtime.serverInfo, !serverInfo.serverBanner.isEmpty {
            return serverInfo.serverBanner
        }

        return nil
    }

    private func scheduleAutoSave() {
        guard canSetSettings else { return }
        guard !isLoading else { return }
        guard !isApplyingSettings else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await saveSettings()
        }
    }

    private func isPermissionDeniedError(_ error: Error) -> Bool {
        if let asyncError = error as? AsyncConnectionError,
           case let .serverError(message) = asyncError {
            let messageText = (message.string(forField: "wired.error.string") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let code = message.uint32(forField: "wired.error")
            return messageText.contains("permission_denied")
                || messageText.contains("permission denied")
                || code == 5
                || code == 57
        }

        if let wiredError = error as? WiredError {
            let messageText = wiredError.message
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return messageText.contains("permission_denied")
                || messageText.contains("permission denied")
        }

        return false
    }
}

private struct TrackerRow: Identifiable, Equatable {
    let id = UUID()
    var url: String
    var login: String
    var password: String
    var category: String
}

private struct BansSettingsView: View {
    let runtime: ConnectionRuntime

    @State private var bans: [BanListEntry] = []
    @State private var selectedBanIDs: Set<BanListEntry.ID> = []
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var lastError: Error?
    @State private var showAddSheet = false

    private var canListBans: Bool {
        runtime.hasPrivilege("wired.account.banlist.get_bans")
    }

    private var canAddBans: Bool {
        runtime.hasPrivilege("wired.account.banlist.add_bans")
    }

    private var canDeleteBans: Bool {
        runtime.hasPrivilege("wired.account.banlist.delete_bans")
    }

    private var selectedEntries: [BanListEntry] {
        bans.filter { selectedBanIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if !canListBans {
                ContentUnavailableView(
                    "Accès refusé",
                    systemImage: "lock",
                    description: Text("Permission requise: wired.account.banlist.get_bans")
                )
            } else {
                content
            }
        }
        .task(id: "\(runtime.userID)-\(canListBans)") {
            guard runtime.userID > 0 else { return }
            await reloadBans()
        }
        .errorAlert(
            error: $lastError,
            source: "Ban List",
            serverName: nil,
            connectionID: runtime.id
        )
        .sheet(isPresented: $showAddSheet) {
            BanListEditorSheet(runtime: runtime) {
                showAddSheet = false
                Task {
                    await reloadBans()
                }
            } onDismiss: {
                showAddSheet = false
            } onError: { error in
                lastError = error
            }
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .disabled(!canAddBans || isMutating)

                Button {
                    deleteSelectedBans()
                } label: {
                    Label("Supprimer", systemImage: "minus")
                }
                .disabled(!canDeleteBans || selectedEntries.isEmpty || isMutating)

                Spacer()

                Button {
                    Task { await reloadBans() }
                } label: {
                    Label("Rafraîchir", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || isMutating)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if bans.isEmpty, !isLoading {
                ContentUnavailableView("Aucun bannissement", systemImage: "minus.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                bansTable
            }
        }
        .overlay {
            if isLoading || isMutating {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var bansTable: some View {
#if os(macOS)
        Table(bans, selection: $selectedBanIDs) {
            TableColumn("IP", value: \.ipPattern)
                .width(min: 220, ideal: 280, max: .infinity)

            TableColumn("Date d'expiration") { entry in
                Text(Self.expirationText(for: entry.expirationDate))
                    .foregroundStyle(entry.expirationDate == nil ? .secondary : .primary)
            }
            .width(min: 160, ideal: 220)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
#else
        List(bans, selection: $selectedBanIDs) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.ipPattern)
                Text(Self.expirationText(for: entry.expirationDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
#endif
    }

    private func reloadBans() async {
        guard canListBans else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            bans = try await runtime.fetchBans()
            let currentIDs = Set(bans.map(\.id))
            selectedBanIDs = selectedBanIDs.intersection(currentIDs)
        } catch {
            lastError = error
        }
    }

    private func deleteSelectedBans() {
        guard !selectedEntries.isEmpty else { return }

        isMutating = true

        Task {
            do {
                for entry in selectedEntries {
                    try await runtime.deleteBan(ipPattern: entry.ipPattern, expirationDate: entry.expirationDate)
                }

                await MainActor.run {
                    selectedBanIDs.removeAll()
                }

                await reloadBans()
            } catch {
                await MainActor.run {
                    lastError = error
                }
            }

            await MainActor.run {
                isMutating = false
            }
        }
    }

    private static func expirationText(for date: Date?) -> String {
        guard let date else { return "Jamais" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct BanListEditorSheet: View {
    let runtime: ConnectionRuntime
    let onSaved: () -> Void
    let onDismiss: () -> Void
    let onError: (Error) -> Void

    @State private var ipPattern = ""
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date().addingTimeInterval(3600)
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ajouter un bannissement")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("IP")
                    .font(.headline)

                TextField("192.168.* ou 192.168.0.0/16", text: $ipPattern)
                    .textFieldStyle(.roundedBorder)

                Text("Les IP exactes, wildcards, CIDR et masques réseau sont acceptés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Expire")
                    .font(.headline)

                Picker("Expire", selection: $hasExpirationDate) {
                    Text("Jamais").tag(false)
                    Text("Date").tag(true)
                }
                .pickerStyle(.segmented)

                if hasExpirationDate {
                    DatePicker(
                        "Date d'expiration",
                        selection: $expirationDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }
            }

            HStack {
                Spacer()

                Button("Annuler") {
                    onDismiss()
                }
                .disabled(isSaving)

                Button("OK") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || ipPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 420)
    }

    private func save() {
        guard !isSaving else { return }

        isSaving = true

        Task {
            do {
                try await runtime.addBan(
                    ipPattern: ipPattern,
                    expirationDate: hasExpirationDate ? expirationDate : nil
                )

                await MainActor.run {
                    isSaving = false
                    onSaved()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    onError(error)
                }
            }
        }
    }
}

private enum EventArchiveScope: Hashable, Identifiable {
    case current
    case archive(Date)

    var id: String {
        switch self {
        case .current:
            return "current"
        case .archive(let date):
            return "archive-\(date.timeIntervalSince1970)"
        }
    }

    func title(calendar: Calendar) -> String {
        switch self {
        case .current:
            return "Évènements récents"
        case .archive(let date):
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            return "Semaine du \(weekStart.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    var fromDate: Date? {
        switch self {
        case .current:
            return nil
        case .archive(let date):
            return date
        }
    }
}

@MainActor
private final class ServerEventsSettingsViewModel: ObservableObject {
    @Published var selectedScope: EventArchiveScope = .current
    @Published var currentEvents: [WiredServerEventRecord] = []
    @Published var archivedEventsByScope: [Date: [WiredServerEventRecord]] = [:]
    @Published var selectedNick: String?
    @Published var selectedLogin: String?
    @Published var selectedIP: String?
    @Published var selectedCategory: WiredServerEventCategory?
    @Published var searchText = ""
    @Published var firstEventDate: Date?
    @Published var isLoading = false
    @Published var error: Error?

    private weak var runtime: ConnectionRuntime?
    private var hasLoadedInitialData = false
    private var isSubscribedToEvents = false
    private let calendar = Calendar.current

    func configure(runtime: ConnectionRuntime) {
        self.runtime = runtime
    }

    var canViewEvents: Bool {
        runtime?.hasPrivilege("wired.account.events.view_events") ?? false
    }

    var availableScopes: [EventArchiveScope] {
        var scopes: [EventArchiveScope] = [.current]
        guard let firstEventDate else { return scopes }

        var cursor = calendar.dateInterval(of: .weekOfYear, for: firstEventDate)?.start ?? firstEventDate
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var archiveScopes: [EventArchiveScope] = []

        while cursor <= currentWeek {
            archiveScopes.append(.archive(cursor))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        scopes.append(contentsOf: archiveScopes.reversed())
        return scopes
    }

    var filteredEvents: [WiredServerEventRecord] {
        activeEvents
            .filter { event in
                if let selectedNick, event.nick != selectedNick { return false }
                if let selectedLogin, event.login != selectedLogin { return false }
                if let selectedIP, event.ip != selectedIP { return false }
                if let selectedCategory, event.category != selectedCategory { return false }

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let haystack = [
                        event.nick,
                        event.login,
                        event.ip,
                        event.messageText,
                        event.protocolName,
                    ]
                    .joined(separator: " ")
                    if !haystack.localizedStandardContains(query) {
                        return false
                    }
                }

                return true
            }
            .sorted { lhs, rhs in
                if lhs.time != rhs.time {
                    return lhs.time > rhs.time
                }
                return lhs.id > rhs.id
            }
    }

    var availableNicks: [String] {
        uniqueValues(\.nick)
    }

    var availableLogins: [String] {
        uniqueValues(\.login)
    }

    var availableIPs: [String] {
        uniqueValues(\.ip)
    }

    var availableCategories: [WiredServerEventCategory] {
        Array(Set(activeEvents.map(\.category))).sorted { $0.title < $1.title }
    }

    func loadIfNeeded() async {
        if !hasLoadedInitialData {
            let didAttemptLoad = await refresh(forceScopeReload: true)
            hasLoadedInitialData = didAttemptLoad
        }

        await subscribeToEventsIfNeeded()
    }

    @discardableResult
    func refresh(forceScopeReload: Bool) async -> Bool {
        guard let runtime, canViewEvents else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            firstEventDate = try await runtime.fetchFirstEventTime()
            currentEvents = try await runtime.fetchCurrentEvents()
            if forceScopeReload, case .archive(let fromDate) = selectedScope {
                archivedEventsByScope[fromDate] = try await runtime.fetchArchivedEvents(from: fromDate)
            }
            normalizeFilters()
        } catch {
            self.error = error
        }

        return true
    }

    func loadSelectedScopeIfNeeded() async {
        guard let runtime, canViewEvents else { return }

        if case .archive(let fromDate) = selectedScope, archivedEventsByScope[fromDate] == nil {
            isLoading = true
            defer { isLoading = false }

            do {
                archivedEventsByScope[fromDate] = try await runtime.fetchArchivedEvents(from: fromDate)
            } catch {
                self.error = error
            }
        }

        normalizeFilters()
    }

    func subscribeToEventsIfNeeded() async {
        guard let runtime, canViewEvents, !isSubscribedToEvents else { return }

        do {
            try await runtime.subscribeToEvents()
            isSubscribedToEvents = true
        } catch let wiredError as WiredError {
            if wiredError.message.contains("already_subscribed") {
                isSubscribedToEvents = true
            } else {
                self.error = wiredError
            }
        } catch {
            self.error = error
        }
    }

    func unsubscribeFromEventsIfNeeded() async {
        guard let runtime, isSubscribedToEvents else { return }

        do {
            try await runtime.unsubscribeFromEvents()
            isSubscribedToEvents = false
        } catch let wiredError as WiredError {
            if wiredError.message.contains("not_subscribed") {
                isSubscribedToEvents = false
            } else {
                self.error = wiredError
            }
        } catch {
            self.error = error
        }
    }

    func handleLiveEvent(_ event: WiredServerEventRecord) {
        guard currentEvents.contains(where: { $0.id == event.id }) == false else { return }
        currentEvents.append(event)
        normalizeFilters()
    }

    private var activeEvents: [WiredServerEventRecord] {
        switch selectedScope {
        case .current:
            return currentEvents
        case .archive(let fromDate):
            return archivedEventsByScope[fromDate] ?? []
        }
    }

    private func uniqueValues(_ keyPath: KeyPath<WiredServerEventRecord, String>) -> [String] {
        let values = activeEvents.map { $0[keyPath: keyPath] }
        let nonEmptyValues = values.filter { !$0.isEmpty }
        let uniqueValues = Set(nonEmptyValues)
        return uniqueValues.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalizeFilters() {
        if let selectedNick, !availableNicks.contains(selectedNick) {
            self.selectedNick = nil
        }
        if let selectedLogin, !availableLogins.contains(selectedLogin) {
            self.selectedLogin = nil
        }
        if let selectedIP, !availableIPs.contains(selectedIP) {
            self.selectedIP = nil
        }
        if let selectedCategory, !availableCategories.contains(selectedCategory) {
            self.selectedCategory = nil
        }
    }
}

private struct ServerEventsSettingsView: View {
    let runtime: ConnectionRuntime

    @StateObject private var viewModel = ServerEventsSettingsViewModel()

    private var hasResolvedPrivileges: Bool {
        !runtime.privileges.isEmpty
    }

    private var canViewEvents: Bool {
        runtime.hasPrivilege("wired.account.events.view_events")
    }

    var body: some View {
        Group {
            if !hasResolvedPrivileges {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !canViewEvents {
                ContentUnavailableView(
                    "Accès refusé",
                    systemImage: "lock",
                    description: Text("Permission requise: wired.account.events.view_events")
                )
            } else {
                content
            }
        }
        .task(id: "\(runtime.userID)-\(runtime.status)-\(canViewEvents)") {
            viewModel.configure(runtime: runtime)
            await viewModel.loadIfNeeded()
            await viewModel.loadSelectedScopeIfNeeded()
        }
        .onChange(of: viewModel.selectedScope) { _, _ in
            Task { await viewModel.loadSelectedScopeIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiredServerEventReceived)) { notification in
            guard let payload = notification.object as? RemoteServerEvent else { return }
            guard payload.connectionID == runtime.id else { return }
            viewModel.handleLiveEvent(payload.event)
        }
        .onDisappear {
            Task {
                await viewModel.unsubscribeFromEventsIfNeeded()
            }
        }
        .errorAlert(
            error: Binding(
                get: { viewModel.error },
                set: { viewModel.error = $0 }
            ),
            source: "Events Settings",
            serverName: nil,
            connectionID: runtime.id
        )
    }

    private var content: some View {
        VStack(spacing: 12) {
            filtersBar

            if viewModel.filteredEvents.isEmpty, !viewModel.isLoading {
                ContentUnavailableView("Aucun évènement", systemImage: "flag")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                eventsTable
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    private var filtersBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Période", selection: $viewModel.selectedScope) {
                    ForEach(viewModel.availableScopes) { scope in
                        Text(scope.title(calendar: .current)).tag(scope)
                    }
                }
                .frame(maxWidth: 260)

                Spacer()

                Button {
                    Task {
                        await viewModel.refresh(forceScopeReload: true)
                        await viewModel.loadSelectedScopeIfNeeded()
                    }
                } label: {
                    Label("Rafraîchir", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }

            HStack(spacing: 10) {
                Picker("Pseudo", selection: $viewModel.selectedNick) {
                    Text("Tous les pseudos").tag(Optional<String>.none)
                    ForEach(viewModel.availableNicks, id: \.self) { nick in
                        Text(nick).tag(Optional(nick))
                    }
                }
                .frame(maxWidth: 180)

                Picker("Identifiant", selection: $viewModel.selectedLogin) {
                    Text("Tous les identifiants").tag(Optional<String>.none)
                    ForEach(viewModel.availableLogins, id: \.self) { login in
                        Text(login).tag(Optional(login))
                    }
                }
                .frame(maxWidth: 180)

                Picker("IP", selection: $viewModel.selectedIP) {
                    Text("Toutes les IP").tag(Optional<String>.none)
                    ForEach(viewModel.availableIPs, id: \.self) { ip in
                        Text(ip).tag(Optional(ip))
                    }
                }
                .frame(maxWidth: 160)

                Picker("Catégorie", selection: $viewModel.selectedCategory) {
                    Text("Toutes les catégories").tag(Optional<WiredServerEventCategory>.none)
                    ForEach(viewModel.availableCategories, id: \.self) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                .frame(maxWidth: 160)

                TextField("Rechercher", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var eventsTable: some View {
#if os(macOS)
        Table(viewModel.filteredEvents) {
            TableColumn("") { event in
                Image(systemName: event.category.systemImageName)
                    .help(event.category.title)
            }
            .width(32)
            .alignment(.center)

            TableColumn("Message") { event in
                Text(event.messageText)
                    .lineLimit(2)
            }
            
            TableColumn("Date et heure") { event in
                Text(event.time.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
            }
            .width(170)

            TableColumn("Pseudonyme") { event in
                Text(event.nick.isEmpty ? " " : event.nick)
            }
            .width(min: 110, ideal: 120, max: 140)

            TableColumn("Identifiant") { event in
                Text(event.login.isEmpty ? " " : event.login)
            }
            .width(min: 110, ideal: 120, max: 140)

            TableColumn("IP") { event in
                Text(event.ip)
                    .monospaced()
            }
            .width(110)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
#else
        List(viewModel.filteredEvents) { event in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: event.category.systemImageName)
                    Text(event.messageText)
                }
                Text("\(event.nick) · \(event.login) · \(event.ip)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.time.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
#endif
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

// MARK: - Server Log

@MainActor
private final class ServerLogSettingsViewModel: ObservableObject {
    @Published var entries: [WiredLogEntry] = []
    @Published var levelFilter: WiredLogLevel? = nil
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var error: Error?

    private weak var runtime: ConnectionRuntime?
    private var hasLoadedInitialData = false
    private var isSubscribedToLog = false

    func configure(runtime: ConnectionRuntime) {
        self.runtime = runtime
    }

    var canViewLog: Bool {
        runtime?.hasPrivilege("wired.account.log.view_log") ?? false
    }

    var filteredEntries: [WiredLogEntry] {
        entries
            .filter { entry in
                if let levelFilter, entry.level != levelFilter { return false }
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return entry.message.localizedStandardContains(query)
                }
                return true
            }
            .sorted { $0.time > $1.time }
    }

    func loadIfNeeded() async {
        if !hasLoadedInitialData {
            let didLoad = await refresh()
            hasLoadedInitialData = didLoad
        }
        await subscribeToLogIfNeeded()
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let runtime, canViewLog else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await runtime.fetchLog()
        } catch {
            self.error = error
        }

        return true
    }

    func subscribeToLogIfNeeded() async {
        guard let runtime, canViewLog, !isSubscribedToLog else { return }

        do {
            try await runtime.subscribeToLog()
            isSubscribedToLog = true
        } catch let wiredError as WiredError {
            if wiredError.message.contains("already_subscribed") {
                isSubscribedToLog = true
            } else {
                self.error = wiredError
            }
        } catch {
            self.error = error
        }
    }

    func unsubscribeFromLogIfNeeded() async {
        guard let runtime, isSubscribedToLog else { return }

        do {
            try await runtime.unsubscribeFromLog()
            isSubscribedToLog = false
        } catch let wiredError as WiredError {
            if wiredError.message.contains("not_subscribed") {
                isSubscribedToLog = false
            } else {
                self.error = wiredError
            }
        } catch {
            self.error = error
        }
    }

    func handleLiveEntry(_ entry: WiredLogEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
    }
}

private struct ServerLogSettingsView: View {
    let runtime: ConnectionRuntime

    @StateObject private var viewModel = ServerLogSettingsViewModel()

    private var hasResolvedPrivileges: Bool {
        !runtime.privileges.isEmpty
    }

    private var canViewLog: Bool {
        runtime.hasPrivilege("wired.account.log.view_log")
    }

    var body: some View {
        Group {
            if !hasResolvedPrivileges {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !canViewLog {
                ContentUnavailableView(
                    "Accès refusé",
                    systemImage: "lock",
                    description: Text("Permission requise: wired.account.log.view_log")
                )
            } else {
                content
            }
        }
        .task(id: "\(runtime.userID)-\(runtime.status)-\(canViewLog)") {
            viewModel.configure(runtime: runtime)
            await viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiredServerLogMessageReceived)) { notification in
            guard let payload = notification.object as? RemoteServerLogEntry else { return }
            guard payload.connectionID == runtime.id else { return }
            viewModel.handleLiveEntry(payload.entry)
        }
        .onDisappear {
            Task { await viewModel.unsubscribeFromLogIfNeeded() }
        }
        .errorAlert(
            error: Binding(
                get: { viewModel.error },
                set: { viewModel.error = $0 }
            ),
            source: "Log Settings",
            serverName: nil,
            connectionID: runtime.id
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            filtersBar

            if viewModel.filteredEntries.isEmpty, !viewModel.isLoading {
                ContentUnavailableView("Aucune entrée", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                logTable
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    private var filtersBar: some View {
        HStack(spacing: 10) {
            Picker("Niveau", selection: $viewModel.levelFilter) {
                Text("Tous les niveaux").tag(Optional<WiredLogLevel>.none)
                ForEach(WiredLogLevel.allCases, id: \.self) { level in
                    Label(level.title, systemImage: level.systemImageName)
                        .tag(Optional(level))
                }
            }
            .frame(maxWidth: 200)

            TextField("Rechercher", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Rafraîchir", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var logTable: some View {
#if os(macOS)
        Table(viewModel.filteredEntries) {
            TableColumn("") { entry in
                Image(systemName: entry.level.systemImageName)
                    .foregroundStyle(levelColor(entry.level))
                    .help(entry.level.title)
            }
            .width(28)
            .alignment(.center)

            TableColumn("Date et heure") { entry in
                Text(entry.time.formatted(date: .abbreviated, time: .standard))
                    .monospacedDigit()
            }
            .width(170)

            TableColumn("Niveau") { entry in
                Text(entry.level.title)
                    .foregroundStyle(levelColor(entry.level))
            }
            .width(70)

            TableColumn("Message") { entry in
                Text(entry.message)
                    .lineLimit(2)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
#else
        List(viewModel.filteredEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: entry.level.systemImageName)
                        .foregroundStyle(levelColor(entry.level))
                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4)
                }
                Text(entry.time.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
#endif
    }

    private func levelColor(_ level: WiredLogLevel) -> Color {
        switch level {
        case .debug:   return .secondary
        case .info:    return .primary
        case .warning: return .yellow
        case .error:   return .red
        }
    }
}
