import SwiftUI

struct FilePreviewColumn: View {
    let selectedItem: FileItem?
    var syncPairStatusForItem: ((FileItem) -> SyncPairStatusDisplay)?
    var syncPairExistsForItem: ((FileItem) -> Bool)?

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor)
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let item = selectedItem {
                VStack(alignment: .leading, spacing: 0) {
                    iconHeader(item)
                    metaSection(item)
                    if item.type == .sync {
                        syncSection(item)
                    }
                }
                .padding(.vertical, 12)
            } else {
                VStack {
                    Spacer(minLength: 60)
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("No Selection")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(backgroundColor)
    }

    // MARK: - Icon + name header

    private func iconHeader(_ item: FileItem) -> some View {
        VStack(spacing: 8) {
            FinderFileIconView(item: item, size: 72)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)

            Text(item.name.isEmpty ? item.path : item.name)
                .font(.subheadline).fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: - Metadata section

    private func metaSection(_ item: FileItem) -> some View {
        previewCard {
            metaRow("Type", item.type.description)
            cardDivider
            metaRow("Size", sizeString(for: item))
            if let created = item.creationDate {
                cardDivider
                metaRow("Created", dateFormatter.string(from: created))
            }
            if let modified = item.modificationDate {
                cardDivider
                metaRow("Modified", dateFormatter.string(from: modified))
            }
            if item.type == .file && item.executable {
                cardDivider
                metaRow("Executable", NSLocalizedString("Yes", comment: ""))
            }
            if item.type.isDirectoryLike {
                cardDivider
                metaRow("Contains", containsString(for: item))
            }
            if item.label != .none {
                cardDivider
                labelRow(item.label)
            }
        }
    }

    private func labelRow(_ label: FileLabelValue) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Label")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(label.color)
                    .frame(width: 8, height: 8)
                Text(label.title)
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(label.color)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Sync section

    private func syncSection(_ item: FileItem) -> some View {
        let status = syncPairStatusForItem?(item) ?? .inactive
        let pairExists = syncPairExistsForItem?(item) ?? false
        let effectiveMode = SyncModeLabel.from(item.syncEffectiveMode)

        return previewCard(title: "Sync Pair", icon: "arrow.2.circlepath") {
            // Status row
            HStack {
                Text("Status")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                syncStatusBadge(status)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            cardDivider

            // Pair active row
            HStack {
                Text("Pair")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(pairExists ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(pairExists ? "Active" : "Inactive")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(pairExists ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            cardDivider

            // Effective mode row
            HStack {
                Text("Mode")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Label(effectiveMode.title, systemImage: effectiveMode.icon)
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func syncStatusBadge(_ status: SyncPairStatusDisplay) -> some View {
        let info = SyncStatusInfo.from(status)
        HStack(spacing: 5) {
            if info.spinning {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: info.icon)
                    .font(.caption2)
                    .foregroundStyle(info.color)
            }
            Text(info.label)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(info.color)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(info.color.opacity(0.10))
        .clipShape(Capsule())
    }

    // MARK: - Card primitives

    private func previewCard<Content: View>(
        title: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, let icon {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption2).fontWeight(.semibold)
                    Text(LocalizedStringKey(title))
                        .font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 5)
            }
            content()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var cardDivider: some View {
        Divider().padding(.horizontal, 12)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func sizeString(for item: FileItem) -> String {
        let total = item.dataSize + item.rsrcSize
        guard total > 0 else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private func containsString(for item: FileItem) -> String {
        guard item.hasDirectoryCount else { return "-" }
        if item.directoryCount == 1 {
            return NSLocalizedString("1 item", comment: "")
        }
        return String(format: NSLocalizedString("%lld items", comment: ""), Int64(item.directoryCount))
    }
}

// MARK: - Sync display helpers

private struct SyncStatusInfo {
    let label: String
    let icon: String
    let color: Color
    let spinning: Bool

    static func from(_ status: SyncPairStatusDisplay) -> SyncStatusInfo {
        switch status {
        case .hidden, .inactive:
            return .init(label: NSLocalizedString("Inactive", comment: ""),     icon: "link.circle",                        color: .secondary, spinning: false)
        case .checking:
            return .init(label: NSLocalizedString("Checking…", comment: ""),    icon: "",                                   color: .secondary, spinning: true)
        case .paused:
            return .init(label: NSLocalizedString("Paused", comment: ""),       icon: "pause.circle.fill",                  color: .orange,    spinning: false)
        case .connecting:
            return .init(label: NSLocalizedString("Connecting…", comment: ""),  icon: "",                                   color: .blue,      spinning: true)
        case .connected:
            return .init(label: NSLocalizedString("Connected", comment: ""),    icon: "checkmark.circle.fill",              color: .green,     spinning: false)
        case .syncing:
            return .init(label: NSLocalizedString("Syncing…", comment: ""),     icon: "",                                   color: .blue,      spinning: true)
        case .reconnecting:
            return .init(label: NSLocalizedString("Reconnecting", comment: ""), icon: "",                                   color: .orange,    spinning: true)
        case .error:
            return .init(label: NSLocalizedString("Error", comment: ""),        icon: "exclamationmark.triangle.fill",      color: .red,       spinning: false)
        }
    }
}

private struct SyncModeLabel {
    let title: String
    let icon: String

    static func from(_ mode: SyncModeValue) -> SyncModeLabel {
        switch mode {
        case .disabled:
            return .init(title: NSLocalizedString("Disabled", comment: ""),        icon: "slash.circle")
        case .serverToClient:
            return .init(title: NSLocalizedString("Server → Client", comment: ""), icon: "arrow.down.circle")
        case .clientToServer:
            return .init(title: NSLocalizedString("Client → Server", comment: ""), icon: "arrow.up.circle")
        case .bidirectional:
            return .init(title: NSLocalizedString("Bidirectional", comment: ""),   icon: "arrow.2.circlepath")
        }
    }
}
