//
//  FileInfoSheet.swift
//  Wired 3
//
//  Created by Codex on 18/02/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

private enum DropboxAccessLevel: String, CaseIterable, Identifiable {
    case denied
    case readWrite
    case readOnly
    case writeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .denied:    return NSLocalizedString("No Access", comment: "")
        case .readWrite: return NSLocalizedString("Read & Write", comment: "")
        case .readOnly:  return NSLocalizedString("Read Only", comment: "")
        case .writeOnly: return NSLocalizedString("Write Only", comment: "")
        }
    }

    var readEnabled: Bool { self == .readWrite || self == .readOnly }
    var writeEnabled: Bool { self == .readWrite || self == .writeOnly }

    static func from(read: Bool, write: Bool) -> DropboxAccessLevel {
        switch (read, write) {
        case (false, false): return .denied
        case (true, true):  return .readWrite
        case (true, false): return .readOnly
        case (false, true):  return .writeOnly
        }
    }
}

private enum SyncAccessMode: String, CaseIterable, Identifiable {
    case disabled       = "disabled"
    case serverToClient = "server_to_client"
    case clientToServer = "client_to_server"
    case bidirectional  = "bidirectional"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:       return NSLocalizedString("Disabled", comment: "")
        case .serverToClient: return NSLocalizedString("Server → Client", comment: "")
        case .clientToServer: return NSLocalizedString("Client → Server", comment: "")
        case .bidirectional:  return NSLocalizedString("Bidirectional", comment: "")
        }
    }

    static func from(mode: SyncModeValue) -> SyncAccessMode {
        SyncAccessMode(rawValue: mode.rawValue) ?? .disabled
    }

    var value: SyncModeValue {
        SyncModeValue(rawValue: rawValue) ?? .disabled
    }
}

struct FileInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    @ObservedObject var filesViewModel: FilesViewModel
    let file: FileItem

    @State private var info: FileItem
    @State private var selectedTypeRawValue: UInt32
    @State private var isLoadingInfo = false
    @State private var isSaving = false
    @State private var isLoadingAccounts = false
    @State private var ownerNames: [String] = []
    @State private var groupNames: [String] = []
    @State private var ownerSelection = ""
    @State private var groupSelection = ""
    @State private var ownerAccess: DropboxAccessLevel = .denied
    @State private var groupAccess: DropboxAccessLevel = .denied
    @State private var everyoneAccess: DropboxAccessLevel = .denied
    @State private var syncOwnerMode: SyncAccessMode = .disabled
    @State private var syncGroupMode: SyncAccessMode = .disabled
    @State private var syncEveryoneMode: SyncAccessMode = .disabled
    @State private var syncMaxFileSizeBytes: UInt64 = 0
    @State private var syncMaxTreeSizeBytes: UInt64 = 0
    @State private var syncExcludePatterns: String = ""
    @State private var newName: String = ""
    @State private var labelSelection: FileLabelValue = .none
    @State private var commentText: String = ""

    init(filesViewModel: FilesViewModel, file: FileItem) {
        self.filesViewModel = filesViewModel
        self.file = file
        _info = State(initialValue: file)
        _selectedTypeRawValue = State(initialValue: file.type.rawValue)
        _newName = State(initialValue: file.name)
    }

    // MARK: - Computed

    private var selectedType: FileType {
        FileType(rawValue: selectedTypeRawValue) ?? .directory
    }

    private var isDirectoryType: Bool { info.type.isDirectoryLike }
    private var isInsideSyncSubtree: Bool { filesViewModel.isInsideSyncTree(info.path) }

    private var availableFolderTypes: [FileType] {
        isInsideSyncSubtree ? [.directory] : [.directory, .uploads, .dropbox, .sync]
    }

    private var canEditType: Bool {
        isDirectoryType && runtime.hasPrivilege("wired.account.file.set_type")
    }

    private var hasManagedPermissionChanges: Bool {
        guard info.type.isManagedAccessType else { return false }
        return ownerSelection   != info.owner
            || groupSelection   != info.group
            || ownerAccess      != .from(read: info.ownerRead, write: info.ownerWrite)
            || groupAccess      != .from(read: info.groupRead, write: info.groupWrite)
            || everyoneAccess   != .from(read: info.everyoneRead, write: info.everyoneWrite)
    }

    private var hasSyncPolicyChanges: Bool {
        guard info.type == .sync else { return false }
        return syncOwnerMode         != .from(mode: info.syncUserMode)
            || syncGroupMode         != .from(mode: info.syncGroupMode)
            || syncEveryoneMode      != .from(mode: info.syncEveryoneMode)
            || syncMaxFileSizeBytes  != info.syncMaxFileSizeBytes
            || syncMaxTreeSizeBytes  != info.syncMaxTreeSizeBytes
            || syncExcludePatterns   != info.syncExcludePatterns
    }

    private var hasRenameChange: Bool {
        !newName.isEmpty && newName != info.name
    }

    private var hasLabelChange: Bool {
        labelSelection != info.label
    }

    private var hasCommentChange: Bool {
        commentText != info.comment
    }

    private var hasChanges: Bool {
        hasRenameChange
        || hasLabelChange
        || hasCommentChange
        || selectedTypeRawValue != info.type.rawValue
        || hasManagedPermissionChanges
        || hasSyncPolicyChanges
    }

    private var canEditManagedPermissions: Bool {
        info.type.isManagedAccessType &&
        (runtime.hasPrivilege("wired.account.file.set_permissions") || info.writable)
    }

    private var canSaveChanges: Bool {
        hasRenameChange
        || (canEditLabel && hasLabelChange)
        || (canEditComment && hasCommentChange)
        || (canEditType && selectedTypeRawValue != info.type.rawValue)
        || (canEditManagedPermissions && hasManagedPermissionChanges)
        || (canEditManagedPermissions && hasSyncPolicyChanges)
    }

    private var canEditLabel: Bool {
        runtime.hasPrivilege("wired.account.file.set_label")
    }

    private var canEditComment: Bool {
        runtime.hasPrivilege("wired.account.file.set_comment")
    }

    private var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(info.dataSize + info.rsrcSize), countStyle: .file)
    }

    private func byteString(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func dateString(_ value: Date?) -> String {
        guard let value else { return "—" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerCard
                    metadataCard

                    if info.type == .file {
                        sizeCard
                    } else {
                        folderCard
                        if info.type.isManagedAccessType {
                            permissionsCard
                            if info.type == .sync {
                                syncPolicyCard
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("File Info")
            .overlay {
                if isLoadingInfo || isLoadingAccounts {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSaveChanges || isSaving)
                }
            }
            .task {
                await loadInfo()
                await loadAccounts()
            }
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 300)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: fileIcon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(info.type == .file ? Color.secondary : Color.accentColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: $newName)
                    .font(.title3).fontWeight(.semibold)
                    .textFieldStyle(.plain)
                    .lineLimit(1)

                Text(info.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    typeBadge
                    if let created = info.creationDate {
                        metaChip("calendar", dateString(created))
                    }
                    if let modified = info.modificationDate {
                        metaChip("clock", dateString(modified))
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.fill.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fileIcon: String {
        switch info.type {
        case .file:     return "doc.fill"
        case .uploads:  return "arrow.up.doc.fill"
        case .dropbox:  return "tray.fill"
        case .sync:     return "arrow.2.circlepath"
        default:        return "folder.fill"
        }
    }

    private var typeBadge: some View {
        Text(info.type.description)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private func metaChip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Metadata Card

    private var metadataCard: some View {
        infoCard(title: "Metadata", systemImage: "tag") {
            HStack {
                Text("Label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(FileLabelValue.allCases) { label in
                        Button {
                            labelSelection = label
                        } label: {
                            Label {
                                Text(label.title)
                            } icon: {
                                Image(nsImage: label.menuDotImage)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(labelSelection.color)
                            .frame(width: 8, height: 8)
                            .opacity(labelSelection == .none ? 0.35 : 1)
                        Text(labelSelection.title)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!canEditLabel)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            cardDivider

            VStack(alignment: .leading, spacing: 6) {
                Text("Comment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $commentText)
                    .font(.body)
                    .frame(minHeight: 84)
                    .scrollContentBackground(.hidden)
                    .disabled(!canEditComment)
                    .foregroundStyle(canEditComment ? .primary : .secondary)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    // MARK: - Size Card

    private var sizeCard: some View {
        infoCard(title: "Size", systemImage: "doc.badge.ellipsis") {
            infoRow("Data", byteString(info.dataSize))
            cardDivider
            infoRow("Resource", byteString(info.rsrcSize))
            cardDivider
            infoRow("Total", totalSizeString)
        }
    }

    // MARK: - Folder Card

    private var folderCard: some View {
        infoCard(title: "Folder", systemImage: "folder") {
            infoRow("Contains", String(format: NSLocalizedString("%lld items", comment: ""), Int64(info.directoryCount)))
            cardDivider
            HStack {
                Text("Type")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $selectedTypeRawValue) {
                    ForEach(availableFolderTypes, id: \.rawValue) { type in
                        Text(type.description).tag(type.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!canEditType)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    // MARK: - Permissions Card

    private var permissionsCard: some View {
        infoCard(title: "Folder Permissions", systemImage: "lock.fill") {
            HStack {
                Text("Account")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(width: labelWidth, alignment: .leading)
                Spacer()
                Text("Access")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6).padding(.bottom, 4)

            cardDivider

            permissionRow(
                label: "Owner",
                nameBinding: $ownerSelection,
                names: ownerNames,
                accessBinding: $ownerAccess
            )
            cardDivider
            permissionRow(
                label: "Group",
                nameBinding: $groupSelection,
                names: groupNames,
                accessBinding: $groupAccess
            )
            cardDivider

            HStack {
                Text("Everyone")
                    .font(.subheadline)
                    .frame(width: labelWidth, alignment: .leading)
                Spacer()
                Picker("", selection: $everyoneAccess) {
                    ForEach(DropboxAccessLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!canEditManagedPermissions)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func permissionRow(
        label: String,
        nameBinding: Binding<String>,
        names: [String],
        accessBinding: Binding<DropboxAccessLevel>
    ) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .frame(width: labelWidth, alignment: .leading)

            Picker("", selection: nameBinding) {
                Text("None").tag("")
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!canEditManagedPermissions || isLoadingAccounts)

            Spacer()

            Picker("", selection: accessBinding) {
                ForEach(DropboxAccessLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!canEditManagedPermissions)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - Sync Policy Card

    private var syncPolicyCard: some View {
        VStack(spacing: 10) {
            infoCard(title: "Sync Policy", systemImage: "arrow.2.circlepath") {
                syncModeRow("Owner", $syncOwnerMode)
                cardDivider
                syncModeRow("Group", $syncGroupMode)
                cardDivider
                syncModeRow("Everyone", $syncEveryoneMode)
                cardDivider

                HStack {
                    Text("Effective Mode")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(SyncAccessMode.from(mode: info.syncEffectiveMode).title)
                        .font(.subheadline).fontWeight(.medium)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }

            infoCard(title: "Quota", systemImage: "gauge.with.needle") {
                quotaByteRow("Max File Size", bytes: $syncMaxFileSizeBytes)
                cardDivider
                quotaByteRow("Max Tree Size", bytes: $syncMaxTreeSizeBytes)
                cardDivider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exclude Patterns")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $syncExcludePatterns)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 56)
                        .scrollContentBackground(.hidden)
                        .disabled(!canEditManagedPermissions)
                        .foregroundStyle(canEditManagedPermissions ? .primary : .secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }

    /// Row for a byte-size quota field. Shows a TextField (numeric) + unit label.
    private func quotaByteRow(_ label: String, bytes: Binding<UInt64>) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
            Spacer()
            if canEditManagedPermissions {
                TextField("0 = unlimited",
                          value: bytes,
                          format: .number)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .frame(width: 120)
                Text("bytes")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(bytes.wrappedValue == 0 ? NSLocalizedString("Unlimited", comment: "") : ByteCountFormatter.string(fromByteCount: Int64(bytes.wrappedValue), countStyle: .file))
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func syncModeRow(_ label: String, _ binding: Binding<SyncAccessMode>) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .frame(width: labelWidth, alignment: .leading)
            Spacer()
            Picker("", selection: binding) {
                ForEach(SyncAccessMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!canEditManagedPermissions)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - Reusable Primitives

    private let labelWidth: CGFloat = 72

    private var cardDivider: some View {
        Divider().padding(.horizontal, 14)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func infoCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 8)

            Divider()

            content()
        }
        .background(.fill.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    @MainActor
    private func loadInfo() async {
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let loadedInfo = try await filesViewModel.getFileInfo(path: file.path)
            info = loadedInfo
            newName = loadedInfo.name
            selectedTypeRawValue = loadedInfo.type.rawValue
            if isInsideSyncSubtree && selectedTypeRawValue != FileType.directory.rawValue {
                selectedTypeRawValue = FileType.directory.rawValue
            }
            ownerSelection   = loadedInfo.owner
            groupSelection   = loadedInfo.group
            labelSelection   = loadedInfo.label
            commentText      = loadedInfo.comment
            ownerAccess      = .from(read: loadedInfo.ownerRead, write: loadedInfo.ownerWrite)
            groupAccess      = .from(read: loadedInfo.groupRead, write: loadedInfo.groupWrite)
            everyoneAccess   = .from(read: loadedInfo.everyoneRead, write: loadedInfo.everyoneWrite)
            syncOwnerMode        = .from(mode: loadedInfo.syncUserMode)
            syncGroupMode        = .from(mode: loadedInfo.syncGroupMode)
            syncEveryoneMode     = .from(mode: loadedInfo.syncEveryoneMode)
            syncMaxFileSizeBytes = loadedInfo.syncMaxFileSizeBytes
            syncMaxTreeSizeBytes = loadedInfo.syncMaxTreeSizeBytes
            syncExcludePatterns  = loadedInfo.syncExcludePatterns
        } catch {
            filesViewModel.error = error
        }
    }

    @MainActor
    private func loadAccounts() async {
        guard info.type.isManagedAccessType else { return }
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }
        do {
            async let users  = filesViewModel.listUserNames()
            async let groups = filesViewModel.listGroupNames()
            ownerNames = try await users
            groupNames = try await groups
        } catch {
            filesViewModel.error = error
        }
    }

    @MainActor
    private func save() async {
        guard hasChanges else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if hasRenameChange {
                let newPath = try await filesViewModel.renameItem(
                    at: info.path,
                    newName: newName,
                    isSyncFolder: info.type == .sync
                )
                // Update local info so subsequent operations use the new path.
                info.path = newPath
                info.name = newName
            }

            if selectedType != info.type, canEditType {
                try await filesViewModel.setFileType(path: info.path, type: selectedType)
            }
            if hasLabelChange, canEditLabel {
                try await filesViewModel.setFileLabel(path: info.path, label: labelSelection)
                info.label = labelSelection
            }
            if hasCommentChange, canEditComment {
                try await filesViewModel.setFileComment(path: info.path, comment: commentText)
                info.comment = commentText
            }
            if info.type.isManagedAccessType, hasManagedPermissionChanges, canEditManagedPermissions {
                let permissions = DropboxPermissions(
                    owner: ownerSelection,
                    group: groupSelection,
                    ownerRead: ownerAccess.readEnabled,
                    ownerWrite: ownerAccess.writeEnabled,
                    groupRead: groupAccess.readEnabled,
                    groupWrite: groupAccess.writeEnabled,
                    everyoneRead: everyoneAccess.readEnabled,
                    everyoneWrite: everyoneAccess.writeEnabled
                )
                try await filesViewModel.setFilePermissions(path: info.path, permissions: permissions)
            }
            if info.type == .sync, hasSyncPolicyChanges, canEditManagedPermissions {
                let policy = SyncPolicyPayload(
                    userMode: syncOwnerMode.value,
                    groupMode: syncGroupMode.value,
                    everyoneMode: syncEveryoneMode.value,
                    maxFileSizeBytes: syncMaxFileSizeBytes,
                    maxTreeSizeBytes: syncMaxTreeSizeBytes,
                    excludePatterns: syncExcludePatterns
                )
                try await filesViewModel.setFileSyncPolicy(path: info.path, policy: policy)
            }
            dismiss()
        } catch {
            filesViewModel.error = error
        }
    }
}

private extension FileLabelValue {
    /// A pre-drawn NSImage circle used in menu items.
    /// SF symbols in menus are always rendered as templates (black) on macOS,
    /// so we draw the dot directly into an NSImage to preserve the color.
    var menuDotImage: NSImage {
        let size: CGFloat = 12
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if self == .none {
                NSColor.tertiaryLabelColor.setFill()
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
                path.lineWidth = 1.5
                NSColor.tertiaryLabelColor.setStroke()
                path.stroke()
            } else {
                NSColor(self.color).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            }
            return true
        }
    }
}
