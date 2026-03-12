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

    let connectionID: UUID

    @State private var selectedCategory: ServerSettingsCategory? = .general

    private var runtime: ConnectionRuntime? {
        connectionController.runtime(for: connectionID)
    }

    var body: some View {
        HSplitView {
            List(ServerSettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.iconName)
                    .tag(category)
            }
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)

            detailContent
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory ?? .accounts {
        case .general:
            if let runtime {
                GeneralServerSettingsView(runtime: runtime)
            } else {
                PlaceholderCategoryView(title: "Réglages")
            }
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
                    .disabled(!canSetSettings || isSaving)
            }

            settingsFieldRow("Description") {
                TextField("", text: $serverDescription)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canSetSettings || isSaving)
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
                Toggle("Enregistrer le serveur auprès des annuaires suivants", isOn: $registerWithTrackers)
                    .toggleStyle(.checkbox)

                trackerTable
                trackerToolbar

                Divider()
                    .padding(.vertical, 4)

                Toggle("Activer l'annuaire", isOn: $trackerEnabled)
                    .toggleStyle(.checkbox)

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
                            .disabled(!canSetSettings || isSaving)
                        TextField("", text: $tracker.login)
                            .disabled(!canSetSettings || isSaving)
                        SecureField("", text: $tracker.password)
                            .disabled(!canSetSettings || isSaving)
                        TextField("", text: $tracker.category)
                            .disabled(!canSetSettings || isSaving)
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

            if let serverInfo = runtime.connection?.serverInfo {
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
        } else if bannerData == nil, let serverInfo = runtime.connection?.serverInfo, !serverInfo.serverBanner.isEmpty {
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

        if let serverInfo = runtime.connection?.serverInfo, !serverInfo.serverBanner.isEmpty {
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
            try? await Task.sleep(for: .milliseconds(450))
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
