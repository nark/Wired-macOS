//
//  ChatAttachmentViews.swift
//  Wired 3
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import Quartz
#endif
#if os(macOS)
import AppKit
#endif

struct ChatDraftAttachmentChipView: View {
    let attachment: ChatDraftAttachment
    let onRemove: () -> Void

    private var iconName: String {
        attachment.isImage ? "photo" : "doc"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            (
                Text(attachment.fileName)
                    .font(.subheadline.weight(.medium))
                +
                Text("  \(attachment.fileSizeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
            .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

enum ChatImageQuickLookSource: Hashable {
    case attachment(ChatAttachmentDescriptor)
    case remote(URL)

    var selectionID: String {
        switch self {
        case .attachment(let attachment):
            return "attachment:\(attachment.id)"
        case .remote(let url):
            return "remote:\(url.absoluteString)"
        }
    }

    var title: String {
        switch self {
        case .attachment(let attachment):
            return attachment.name
        case .remote(let url):
            let filename = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return filename.isEmpty ? "Image" : filename
        }
    }

    var preferredFilenameExtension: String? {
        switch self {
        case .attachment(let attachment):
            return attachment.preferredFilenameExtension
        case .remote(let url):
            let pathExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            return pathExtension.isEmpty ? nil : pathExtension
        }
    }

#if os(macOS)
    func cachedQuickLookURL(
        connectionID: UUID,
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        let cacheDirectory = baseDirectory.appendingPathComponent("ChatQuickLook", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let fileStem = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Preview"
        let suffix = abs(selectionID.hashValue)
        let fileExtension = preferredFilenameExtension ?? "bin"
        return cacheDirectory.appendingPathComponent(
            "\(fileStem)-\(connectionID.uuidString.lowercased())-\(suffix).\(fileExtension)",
            isDirectory: false
        )
    }

    func quickLookURL(connectionID: UUID, runtime: ConnectionRuntime) async throws -> URL {
        let cacheURL = cachedQuickLookURL(connectionID: connectionID)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let data: Data
        switch self {
        case .attachment(let attachment):
            data = try await runtime.downloadChatAttachmentData(attachment)
        case .remote(let url):
            if let cached = await ChatRemoteImageCache.shared.data(for: url) {
                data = cached
            } else {
                let (remoteData, _) = try await URLSession.shared.data(from: url)
                await ChatRemoteImageCache.shared.store(remoteData, for: url)
                data = remoteData
            }
        }

        try data.write(to: cacheURL, options: .atomic)
        return cacheURL
    }
#endif
}

#if os(macOS)
private final class ChatImageQuickLookPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}

final class ChatImageQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var previewItem: ChatImageQuickLookPreviewItem?
    private var sourceFrame: NSRect = .zero

    @MainActor
    func present(localURL: URL, title: String, sourceFrame: NSRect = .zero) {
        previewItem = ChatImageQuickLookPreviewItem(url: localURL, title: title)
        self.sourceFrame = sourceFrame

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.refreshCurrentPreviewItem()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItem
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor previewItem: QLPreviewItem!) -> NSRect {
        sourceFrame
    }
}

private struct ChatQuickLookSpaceKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onSpace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onSpace: onSpace)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onSpace = onSpace
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onSpace: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(isEnabled: Bool, onSpace: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onSpace = onSpace
        }

        deinit {
            detach()
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.isEnabled else { return event }
                guard self.view?.window?.isKeyWindow == true else { return event }
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                      event.keyCode == 49 else {
                    return event
                }

                if let textView = self.view?.window?.firstResponder as? NSTextView,
                   textView.isEditable {
                    return event
                }

                self.onSpace()
                return nil
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif

struct ChatAttachmentImageBubbleView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    let attachment: ChatAttachmentDescriptor
    let isFromYou: Bool
    let showsTail: Bool
    var maxBubbleWidth: CGFloat = 280
    var maxBubbleHeight: CGFloat = 360
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    var onOpenQuickLook: (() -> Void)?
    /// When set and the connected peer/user can post chat reactions, the
    /// context menu shows an "Add Reaction…" entry that opens the emoji
    /// picker anchored on this bubble.
    var chatEvent: ChatEvent?

    @State private var phase: Phase = .idle
    @State private var showReactionPicker = false

    enum Phase {
        case idle
        case loading
        case success(PlatformImage)
        case failure
    }

    private func resolvedSize(for image: PlatformImage) -> CGSize {
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return placeholderSize }
        let ratio = natural.height / natural.width
        var width = min(natural.width, maxBubbleWidth)
        var height = width * ratio
        if height > maxBubbleHeight {
            height = maxBubbleHeight
            width = height / ratio
        }
        return CGSize(width: ceil(width), height: ceil(height))
    }

    private var currentSize: CGSize {
        if case .success(let image) = phase {
            return resolvedSize(for: image)
        }
        return placeholderSize
    }

    private var placeholderSize: CGSize {
        CGSize(width: maxBubbleWidth, height: min(maxBubbleHeight, maxBubbleWidth * 0.68))
    }

    var body: some View {
        bubbleContent
            .frame(width: currentSize.width, height: currentSize.height)
            .mask(bubbleMask)
            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
            .overlay(selectionOverlay)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
            }
            .onTapGesture(count: 2) {
                onSelect?()
                onOpenQuickLook?()
            }
            .contextMenu {
                if canAddReaction {
                    Button {
                        showReactionPicker = true
                    } label: {
                        Label("Add Reaction…", systemImage: "face.smiling")
                    }
                    Divider()
                }
#if os(macOS)
                Button {
                    downloadAttachment()
                } label: {
                    Label("Download Image", systemImage: "square.and.arrow.down")
                }
#endif
            }
            .popover(
                isPresented: $showReactionPicker,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                EmojiPickerPopover { emoji in
                    showReactionPicker = false
                    if let event = chatEvent {
                        Task { try? await runtime.toggleChatReaction(emoji: emoji, on: event) }
                    }
                }
            }
            .task(id: attachment.id) {
                await load()
            }
    }

    private var canAddReaction: Bool {
        guard let event = chatEvent, event.serverMessageID != nil else { return false }
        return runtime.canUseChatReactions
    }

    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.accentColor.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
            .padding(1)
    }

    private var bubbleContent: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.secondary.opacity(0.18),
                    Color.secondary.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            switch phase {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.regular)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            case .success(let image):
                imageView(image)
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3)
                    Text(attachment.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private var bubbleMask: some View {
        MessageBubble(showsTail: showsTail)
            .fill(Color.white)
            .rotation3DEffect(isFromYou ? .degrees(0) : .degrees(180), axis: (x: 0, y: 1, z: 0))
    }

    @ViewBuilder
    private func imageView(_ image: PlatformImage) -> some View {
        let size = resolvedSize(for: image)
        Group {
#if os(iOS)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
#else
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
#endif
        }
        .frame(width: size.width, height: size.height)
    }

    @MainActor
    private func load() async {
        guard case .idle = phase else { return }
        phase = .loading

        do {
            let data = try await runtime.imageData(for: attachment)
            guard let image = AppImageCodec.platformImage(from: data) else {
                phase = .failure
                return
            }
            phase = .success(image)
        } catch {
            phase = .failure
        }
    }

#if os(macOS)
    @MainActor
    private func downloadAttachment() {
        Task {
            do {
                let data = try await runtime.downloadChatAttachmentData(attachment)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = attachment.name
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let saveURL = panel.url {
                    try data.write(to: saveURL, options: .atomic)
                }
            } catch {
                runtime.lastError = error
            }
        }
    }
#endif
}

struct ChatAttachmentFileBubbleView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    let attachment: ChatAttachmentDescriptor
    let isFromYou: Bool
    let showsTail: Bool
    /// When set and reactions are enabled, a context-menu entry on the
    /// bubble opens the emoji picker anchored on it.
    var chatEvent: ChatEvent?

    @State private var isSaving = false
    @State private var showReactionPicker = false

    private var iconName: String {
        if attachment.isImage {
            return "photo"
        }

        if attachment.mediaType.lowercased().hasPrefix("audio/") {
            return "waveform"
        }

        if attachment.mediaType.lowercased().hasPrefix("video/") {
            return "film"
        }

        if attachment.mediaType.lowercased().contains("pdf") {
            return "doc.richtext"
        }

        return "doc"
    }

    var body: some View {
        HStack {
            if isFromYou { Spacer(minLength: 36) }

            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(isFromYou ? .white : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    Text(attachment.fileSizeDescription)
                        .font(.caption)
                        .foregroundStyle(isFromYou ? Color.white.opacity(0.8) : .secondary)
                }

#if os(macOS)
                Button {
                    saveAttachment()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isFromYou ? .white : Color.accentColor)
#endif
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                MessageBubble(showsTail: showsTail)
                    .fill(isFromYou ? Color.accentColor : Color.gray.opacity(0.12))
                    .rotation3DEffect(isFromYou ? .degrees(0) : .degrees(180), axis: (x: 0, y: 1, z: 0))
            )
            .foregroundStyle(isFromYou ? .white : .primary)
            .frame(maxWidth: 320, alignment: isFromYou ? .trailing : .leading)

            if !isFromYou { Spacer(minLength: 36) }
        }
        .contextMenu {
            if canAddReaction {
                Button {
                    showReactionPicker = true
                } label: {
                    Label("Add Reaction…", systemImage: "face.smiling")
                }
            }
        }
        .popover(
            isPresented: $showReactionPicker,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            EmojiPickerPopover { emoji in
                showReactionPicker = false
                if let event = chatEvent {
                    Task { try? await runtime.toggleChatReaction(emoji: emoji, on: event) }
                }
            }
        }
    }

    private var canAddReaction: Bool {
        guard let event = chatEvent, event.serverMessageID != nil else { return false }
        return runtime.canUseChatReactions
    }

#if os(macOS)
    @MainActor
    private func saveAttachment() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            defer { Task { @MainActor in isSaving = false } }

            do {
                let data = try await runtime.downloadChatAttachmentData(attachment)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = attachment.name
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let saveURL = panel.url {
                    try data.write(to: saveURL, options: .atomic)
                }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                }
            }
        }
    }
#endif
}

#if os(macOS)
extension View {
    @ViewBuilder
    func chatQuickLookSpaceMonitor(
        isEnabled: Bool,
        onSpace: @escaping () -> Void
    ) -> some View {
        background(
            ChatQuickLookSpaceKeyMonitor(
                isEnabled: isEnabled,
                onSpace: onSpace
            )
            .frame(width: 0, height: 0)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
