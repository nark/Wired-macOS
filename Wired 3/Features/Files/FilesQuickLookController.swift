#if os(macOS)
import AppKit
import Foundation
import Quartz
import WiredSwift

private final class FilesQuickLookPreviewItem: NSObject, QLPreviewItem {
    let item: FileItem
    let cacheURL: URL
    let title: String
    var previewItemURL: URL?

    init(item: FileItem, cacheURL: URL) {
        self.item = item
        self.cacheURL = cacheURL
        self.title = item.name
        self.previewItemURL = FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil
    }

    var previewItemTitle: String? {
        title
    }
}

final class FilesQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    typealias SourceFrameProvider = (String) -> NSRect?
    typealias WindowProvider = () -> NSWindow?
    typealias ConnectionProvider = () -> AsyncConnection?

    private let connectionID: UUID
    private let fileService: FileServiceProtocol
    private let baseDirectory: URL
    private let sourceFrameProvider: SourceFrameProvider
    private let windowProvider: WindowProvider
    private let connectionProvider: ConnectionProvider
    private var previewItems: [FilesQuickLookPreviewItem] = []
    private var activeRequests: [String: Task<Void, Never>] = [:]

    init(
        connectionID: UUID,
        fileService: FileServiceProtocol = FileService(),
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        sourceFrameProvider: @escaping SourceFrameProvider,
        windowProvider: @escaping WindowProvider,
        connectionProvider: @escaping ConnectionProvider = { nil }
    ) {
        self.connectionID = connectionID
        self.fileService = fileService
        self.baseDirectory = baseDirectory
        self.sourceFrameProvider = sourceFrameProvider
        self.windowProvider = windowProvider
        self.connectionProvider = connectionProvider
    }

    deinit {
        activeRequests.values.forEach { $0.cancel() }
    }

    @MainActor
    func present(
        orderedItems: [FileItem],
        selectedPaths: Set<String>,
        preferredPath: String?
    ) {
        let selectedItems = RemoteQuickLookSupport.selectedPreviewableItems(
            from: orderedItems,
            selectedPaths: selectedPaths
        )
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        do {
            let cacheDirectory = RemoteQuickLookSupport.cacheDirectory(baseDirectory: baseDirectory)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            presentError(error)
            return
        }

        let uncachedLargeItems = selectedItems.filter { item in
            let cacheURL = RemoteQuickLookSupport.previewURL(
                baseDirectory: baseDirectory,
                connectionID: connectionID,
                item: item
            )
            let hasCachedPreview = FileManager.default.fileExists(atPath: cacheURL.path)
            return RemoteQuickLookSupport.shouldConfirmDownload(for: item, hasCachedPreview: hasCachedPreview)
        }
        guard confirmPreviewDownloadIfNeeded(for: uncachedLargeItems) else {
            return
        }

        activeRequests.values.forEach { $0.cancel() }
        activeRequests.removeAll()
        previewItems = selectedItems.map {
            FilesQuickLookPreviewItem(
                item: $0,
                cacheURL: RemoteQuickLookSupport.previewURL(
                    baseDirectory: baseDirectory,
                    connectionID: connectionID,
                    item: $0
                )
            )
        }

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()

        let initialIndex = RemoteQuickLookSupport.initialSelectionIndex(
            items: previewItems.map(\.item),
            preferredPath: preferredPath
        )
        panel.currentPreviewItemIndex = initialIndex

        let prioritizedItems = previewItems.enumerated().sorted { lhs, rhs in
            let lhsIsCurrent = lhs.offset == initialIndex
            let rhsIsCurrent = rhs.offset == initialIndex
            if lhsIsCurrent != rhsIsCurrent {
                return lhsIsCurrent
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        for previewItem in prioritizedItems where previewItem.previewItemURL == nil {
            requestPreview(for: previewItem)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewItems.indices.contains(index) else { return nil }
        return previewItems[index]
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor previewItem: QLPreviewItem!) -> NSRect {
        guard let item = previewItem as? FilesQuickLookPreviewItem,
              let rect = sourceFrameProvider(item.item.path) else {
            return .zero
        }
        return rect
    }

    private func requestPreview(for previewItem: FilesQuickLookPreviewItem) {
        guard let connection = previewItem.item.connection ?? connectionProvider() else { return }

        activeRequests[previewItem.item.path] = Task { [weak self] in
            guard let self else { return }
            defer { self.activeRequests.removeValue(forKey: previewItem.item.path) }

            do {
                let data = try await fileService.previewFile(path: previewItem.item.path, connection: connection)
                if Task.isCancelled { return }
                try data.write(to: previewItem.cacheURL, options: .atomic)
                previewItem.previewItemURL = previewItem.cacheURL
                await MainActor.run {
                    if let panel = QLPreviewPanel.shared(), panel.isVisible {
                        panel.reloadData()

                        let isCurrentPreviewItem =
                            panel.currentPreviewItemIndex >= 0 &&
                            panel.currentPreviewItemIndex < self.previewItems.count &&
                            self.previewItems[panel.currentPreviewItemIndex].item.path == previewItem.item.path

                        if isCurrentPreviewItem {
                            panel.refreshCurrentPreviewItem()
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.presentError(error)
                }
            }
        }
    }

    @MainActor
    private func confirmPreviewDownloadIfNeeded(for items: [FileItem]) -> Bool {
        guard !items.isEmpty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        if items.count == 1, let item = items.first {
            alert.messageText = NSLocalizedString("Download Preview?", comment: "")
            let format = NSLocalizedString(
                "%@ is not cached yet and is larger than 512 KB.\nWired will fetch a lightweight Quick Look preview from the server.",
                comment: "")
            alert.informativeText = String(format: format, item.name)
        } else {
            alert.messageText = NSLocalizedString("Download Previews?", comment: "")
            let format = NSLocalizedString(
                "%lld selected files are not cached yet and are larger than 512 KB.\nWired will fetch lightweight Quick Look previews from the server.",
                comment: "")
            alert.informativeText = String(format: format, Int64(items.count))
        }
        alert.addButton(withTitle: NSLocalizedString("Preview", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func presentError(_ error: Error) {
        let nsError = error as NSError
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Quick Look Error", comment: "")
        alert.informativeText = nsError.localizedDescription
        if let window = windowProvider() {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
#endif
