#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ObjectiveC
import WiredSwift

private final class FileLabelDotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = min(frameRect.width, frameRect.height) / 2
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    func configure(label: FileLabelValue) {
        if label == .none {
            isHidden = true
            toolTip = nil
            return
        }

        isHidden = false
        layer?.backgroundColor = label.nsColor.cgColor
        toolTip = label.title
    }
}

private final class QuickLookTableView: NSTableView {
    var onQuickLook: (() -> Void)?
    var onDraggingExited: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 49 {
            onQuickLook?()
            return
        }

        super.keyDown(with: event)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDraggingExited?()
        super.draggingExited(sender)
    }
}

fileprivate enum RemoteDropOperationBadgeKind {
    case move
    case link

    var title: String {
        switch self {
        case .move:
            return "Move"
        case .link:
            return "Link"
        }
    }

    var symbolName: String {
        switch self {
        case .move:
            return "arrow.right"
        case .link:
            return "link"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .move:
            return .systemBlue
        case .link:
            return .systemGreen
        }
    }
}

private final class RemoteDropOperationBadgeView: NSVisualEffectView {
    private let imageView = NSImageView()
    private let textField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        stack.addArrangedSubview(imageView)

        textField.font = .systemFont(ofSize: 12, weight: .semibold)
        textField.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textField)

        addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ kind: RemoteDropOperationBadgeKind) {
        textField.stringValue = kind.title
        textField.textColor = kind.tintColor
        imageView.contentTintColor = kind.tintColor
        imageView.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title)
    }
}

private final class RemoteColumnDropHighlightView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct AppKitFileColumnTableView: NSViewRepresentable {
    let bookmarkID: UUID
    let quickLookConnection: AsyncConnection?
    let transferManager: TransferManager
    let onDownloadTransferError: (FileItem, String) -> Void
    let column: FileColumn
    let selectedPaths: Set<String>
    let onSelectionChange: (Set<String>, String?) -> Void
    let onDownloadSingleFile: (FileItem) -> Void
    let onUploadURLs: ([URL], FileItem) -> Void
    let onMoveRemoteItem: (_ sourcePath: String, _ destinationDirectory: FileItem, _ link: Bool) async throws -> Void
    let onRequestCreateFolder: (FileItem) -> Void
    let onRequestUploadInDirectory: (FileItem) -> Void
    let onRequestDeleteSelection: ([FileItem]) -> Void
    let onRequestDownloadSelection: ([FileItem]) -> Void
    let onRequestGetInfo: (FileItem) -> Void
    let onRequestSyncNow: (FileItem) -> Void
    let onRequestActivateSync: (FileItem) -> Void
    let onRequestDeactivateSync: (FileItem) -> Void
    let syncPairStatusForItem: (FileItem) -> SyncPairStatusDisplay
    let syncPairExistsForItem: (FileItem) -> Bool
    let syncPairStatusVersion: Int
    let canSetFileType: Bool
    let canGetInfoForItem: (FileItem) -> Bool
    let canDownloadForItem: (FileItem) -> Bool
    let canDeleteForItem: (FileItem) -> Bool
    let canUploadToDirectory: (FileItem) -> Bool
    let canCreateFolderInDirectory: (FileItem) -> Bool
    let canDropRemoteItem: (String, FileItem, Bool) -> Bool
    let canSetLabel: Bool
    let onRequestSetLabel: ([FileItem], FileLabelValue) -> Void
    let savedScrollOffset: CGFloat
    let onScrollOffsetChange: (CGFloat) -> Void
    let onDesiredWidthChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = QuickLookTableView()
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 26
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask([.move, .copy, .link], forLocal: true)
        tableView.registerForDraggedTypes([.fileURL, wiredRemotePathPasteboardType])
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.didDoubleClick(_:))
        tableView.onQuickLook = { [weak coordinator = context.coordinator] in
            coordinator?.presentQuickLook()
        }
        tableView.onDraggingExited = { [weak coordinator = context.coordinator] in
            coordinator?.clearDropState()
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ColumnName"))
        column.title = NSLocalizedString("Name", comment: "")
        column.minWidth = 220
        column.width = 300
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        let menu = context.coordinator.makeContextMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.syncFromModel(items: self.column.items, selectedPaths: selectedPaths, syncPairStatusVersion: syncPairStatusVersion)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        let offsetToRestore = CGPoint(x: 0, y: savedScrollOffset)
        DispatchQueue.main.async {
            scrollView.contentView.scroll(to: offsetToRestore)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncFromModel(items: self.column.items, selectedPaths: selectedPaths, syncPairStatusVersion: syncPairStatusVersion)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, FileLabelMenuTarget {
        var parent: AppKitFileColumnTableView
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        private var items: [FileItem] = []
        private var byPath: [String: Int] = [:]
        private var lastItemSnapshots: [String] = []
        private var lastSyncPairStatusVersion: Int = -1
        private var isApplyingSelectionFromSwiftUI = false
        private var contextDirectoryTarget: FileItem
        private weak var dropBadgeView: RemoteDropOperationBadgeView?
        private weak var dropHighlightView: RemoteColumnDropHighlightView?
        private var activeDropTargetRow: Int?
        private lazy var quickLookController = FilesQuickLookController(
            connectionID: parent.bookmarkID,
            sourceFrameProvider: { [weak self] path in
                self?.sourceFrameOnScreen(for: path)
            },
            windowProvider: { [weak self] in
                self?.tableView?.window
            },
            connectionProvider: { [weak self] in
                self?.parent.quickLookConnection
            }
        )

        init(parent: AppKitFileColumnTableView) {
            self.parent = parent
            self.contextDirectoryTarget = FileItem((parent.column.path as NSString).lastPathComponent, path: parent.column.path, type: .directory)
        }

        @objc func handleScrollChange(_ notification: Notification) {
            guard let sv = scrollView else { return }
            parent.onScrollOffsetChange(sv.contentView.bounds.origin.y)
        }

        private func isDirectory(_ item: FileItem) -> Bool {
            item.type.isDirectoryLike
        }

        private func columnDirectory() -> FileItem {
            FileItem((parent.column.path as NSString).lastPathComponent, path: parent.column.path, type: .directory)
        }

        private func desiredColumnWidth(for items: [FileItem]) -> CGFloat {
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let longestTextWidth = items.reduce(CGFloat(0)) { partial, item in
                let width = (item.name as NSString).size(withAttributes: [.font: font]).width
                return max(partial, width)
            }
            let paddedWidth = longestTextWidth + 64 + 24
            return min(max(220, ceil(paddedWidth)), 420)
        }

        private func itemSnapshot(for item: FileItem) -> String {
            let modified = item.modificationDate?.timeIntervalSinceReferenceDate ?? -1
            return [
                item.path,
                item.name,
                String(item.type.rawValue),
                String(item.directoryCount),
                String(item.hasDirectoryCount),
                String(item.dataSize),
                String(item.rsrcSize),
                String(modified),
                String(item.label.rawValue)
            ].joined(separator: "|")
        }

        func syncFromModel(items: [FileItem], selectedPaths: Set<String>, syncPairStatusVersion: Int) {
            let newSnapshots = items.map(itemSnapshot(for:))
            let listChanged = newSnapshots != lastItemSnapshots
            let syncStatusChanged = syncPairStatusVersion != lastSyncPairStatusVersion
            lastItemSnapshots = newSnapshots
            lastSyncPairStatusVersion = syncPairStatusVersion
            self.items = items
            var map: [String: Int] = [:]
            for (index, item) in items.enumerated() {
                map[item.path] = index
            }
            self.byPath = map
            contextDirectoryTarget = columnDirectory()
            if let tv = tableView, let tableColumn = tv.tableColumns.first {
                let desired = desiredColumnWidth(for: items)
                tableColumn.minWidth = 180
                tv.sizeLastColumnToFit()
                // Notify SwiftUI so it widens the column frame to fit the content.
                // Deferred to avoid mutating state during a view update pass.
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onDesiredWidthChange(desired)
                }
            }
            if listChanged {
                tableView?.reloadData()
            } else if syncStatusChanged {
                let syncRows = IndexSet(items.indices.filter { items[$0].type == .sync })
                if !syncRows.isEmpty {
                    tableView?.reloadData(forRowIndexes: syncRows, columnIndexes: IndexSet(integer: 0))
                }
            }
            updateSelection(selectedPaths)
        }

        private func updateSelection(_ selectedPaths: Set<String>) {
            guard let tableView else { return }
            var indexSet = IndexSet()
            for path in selectedPaths {
                if let row = byPath[path] {
                    indexSet.insert(row)
                }
            }

            if tableView.selectedRowIndexes != indexSet {
                isApplyingSelectionFromSwiftUI = true
                tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
                isApplyingSelectionFromSwiftUI = false
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < items.count else { return nil }
            let item = items[row]
            let id = NSUserInterfaceItemIdentifier("ColumnCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                let cell = NSTableCellView()
                cell.identifier = id
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.imageScaling = .scaleProportionallyUpOrDown
                cell.imageView = icon

                let labelDot = FileLabelDotView(frame: .zero)
                labelDot.identifier = NSUserInterfaceItemIdentifier("FileLabelDot")
                labelDot.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(labelDot)

                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                tf.lineBreakMode = .byTruncatingMiddle
                cell.addSubview(tf)
                cell.textField = tf
                cell.addSubview(icon)

                let statusIcon = NSImageView()
                statusIcon.identifier = NSUserInterfaceItemIdentifier("SyncStatusIcon")
                statusIcon.translatesAutoresizingMaskIntoConstraints = false
                statusIcon.imageScaling = .scaleProportionallyUpOrDown
                cell.addSubview(statusIcon)

                let statusSpinner = NSProgressIndicator()
                statusSpinner.identifier = NSUserInterfaceItemIdentifier("SyncStatusSpinner")
                statusSpinner.translatesAutoresizingMaskIntoConstraints = false
                statusSpinner.controlSize = .regular
                statusSpinner.style = .spinning
                statusSpinner.isDisplayedWhenStopped = false
                cell.addSubview(statusSpinner)

                let chevron = NSImageView()
                chevron.identifier = NSUserInterfaceItemIdentifier("ChevronView")
                chevron.translatesAutoresizingMaskIntoConstraints = false
                chevron.imageScaling = .scaleProportionallyUpOrDown
                chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                chevron.contentTintColor = .tertiaryLabelColor
                cell.addSubview(chevron)

                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    icon.heightAnchor.constraint(equalToConstant: 16),
                    tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    chevron.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    chevron.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    chevron.widthAnchor.constraint(equalToConstant: 7),
                    chevron.heightAnchor.constraint(equalToConstant: 11),
                    labelDot.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -5),
                    labelDot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    labelDot.widthAnchor.constraint(equalToConstant: 8),
                    labelDot.heightAnchor.constraint(equalToConstant: 8),
                    tf.trailingAnchor.constraint(lessThanOrEqualTo: statusIcon.leadingAnchor, constant: -6),
                    tf.trailingAnchor.constraint(lessThanOrEqualTo: statusSpinner.leadingAnchor, constant: -6),
                    tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    statusIcon.trailingAnchor.constraint(equalTo: labelDot.leadingAnchor, constant: -8),
                    statusIcon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    statusIcon.widthAnchor.constraint(equalToConstant: 16),
                    statusIcon.heightAnchor.constraint(equalToConstant: 16),
                    statusSpinner.trailingAnchor.constraint(equalTo: labelDot.leadingAnchor, constant: -8),
                    statusSpinner.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    statusSpinner.widthAnchor.constraint(equalToConstant: 16),
                    statusSpinner.heightAnchor.constraint(equalToConstant: 16)
                ])
                return cell
            }()

            cell.textField?.stringValue = item.name
            cell.imageView?.image = remoteItemIconImage(for: item, size: 16)
            let labelDot = cell.subviews.compactMap { $0 as? FileLabelDotView }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("FileLabelDot") })
            labelDot?.configure(label: item.label)
            let chevronView = cell.subviews.compactMap { $0 as? NSImageView }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("ChevronView") })
            chevronView?.isHidden = !isDirectory(item)
            let statusIcon = cell.subviews.compactMap { $0 as? NSImageView }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("SyncStatusIcon") })
            let statusSpinner = cell.subviews.compactMap { $0 as? NSProgressIndicator }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("SyncStatusSpinner") })
            switch parent.syncPairStatusForItem(item) {
            case .hidden:
                statusIcon?.isHidden = true
                statusSpinner?.stopAnimation(nil)
                cell.toolTip = nil
            case .checking:
                statusIcon?.isHidden = true
                statusSpinner?.isHidden = false
                statusSpinner?.startAnimation(nil)
                cell.toolTip = NSLocalizedString("Sync status pending", comment: "")
            case .paused:
                statusSpinner?.stopAnimation(nil)
                statusIcon?.isHidden = false
                statusIcon?.contentTintColor = .secondaryLabelColor
                statusIcon?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Pair paused")
                cell.toolTip = NSLocalizedString("Sync paused", comment: "")
            case .connecting, .syncing, .reconnecting:
                statusIcon?.isHidden = true
                statusSpinner?.isHidden = false
                statusSpinner?.startAnimation(nil)
                cell.toolTip = parent.syncPairStatusForItem(item) == .reconnecting ? NSLocalizedString("Sync reconnecting", comment: "") : NSLocalizedString("Sync in progress", comment: "")
            case .connected:
                statusSpinner?.stopAnimation(nil)
                statusIcon?.isHidden = false
                statusIcon?.contentTintColor = .systemGreen
                statusIcon?.image = NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: "Pair connected")
                cell.toolTip = NSLocalizedString("Sync connected", comment: "")
            case .error(let message):
                statusSpinner?.stopAnimation(nil)
                statusIcon?.isHidden = false
                statusIcon?.contentTintColor = .systemOrange
                statusIcon?.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Pair error")
                cell.toolTip = message ?? NSLocalizedString("Sync error", comment: "")
            case .inactive:
                statusSpinner?.stopAnimation(nil)
                statusIcon?.isHidden = false
                statusIcon?.contentTintColor = .secondaryLabelColor
                statusIcon?.image = NSImage(systemSymbolName: "link.circle", accessibilityDescription: "Pair inactive")
                cell.toolTip = NSLocalizedString("Sync inactive", comment: "")
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            if isApplyingSelectionFromSwiftUI { return }
            guard let tableView else { return }

            let selectedRows = tableView.selectedRowIndexes
            var paths = Set<String>()
            for row in selectedRows where row >= 0 && row < items.count {
                paths.insert(items[row].path)
            }

            let primary: String? = {
                if tableView.clickedRow >= 0 && tableView.clickedRow < items.count && selectedRows.contains(tableView.clickedRow) {
                    return items[tableView.clickedRow].path
                }
                if let first = selectedRows.first, first >= 0 && first < items.count {
                    return items[first].path
                }
                return nil
            }()

            parent.onSelectionChange(paths, primary)
        }

        @objc
        func didDoubleClick(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0 && row < items.count else { return }
            let item = items[row]
            if !isDirectory(item), parent.canDownloadForItem(item) {
                parent.onDownloadSingleFile(item)
            }
        }

        func presentQuickLook() {
            let orderedItems = items
            let selectedPaths = Set(selectedItems().map(\.path))
            let preferredPath = primarySelectionPath()
            Task { @MainActor [quickLookController] in
                quickLookController.present(
                    orderedItems: orderedItems,
                    selectedPaths: selectedPaths,
                    preferredPath: preferredPath
                )
            }
        }

        private func primarySelectionPath() -> String? {
            guard let tableView else { return nil }
            let selectedRows = tableView.selectedRowIndexes
            if tableView.clickedRow >= 0,
               tableView.clickedRow < items.count,
               selectedRows.contains(tableView.clickedRow) {
                return items[tableView.clickedRow].path
            }
            if let first = selectedRows.first, first >= 0, first < items.count {
                return items[first].path
            }
            return nil
        }

        private func sourceFrameOnScreen(for path: String) -> NSRect? {
            guard let tableView,
                  let row = byPath[path],
                  row >= 0 else { return nil }
            let rowRect = tableView.rect(ofRow: row)
            guard !rowRect.isEmpty else { return nil }
            let rectInWindow = tableView.convert(rowRect, to: nil)
            return tableView.window?.convertToScreen(rectInWindow)
        }

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to _: NSPasteboard) -> Bool {
            let selectedRows = rowIndexes.compactMap { ($0 >= 0 && $0 < items.count) ? $0 : nil }
            return !selectedRows.isEmpty
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row >= 0 && row < items.count else { return nil }
            let item = items[row]
            let isDir = isDirectory(item)
            let fileType: String
            if isDir {
                fileType = UTType.folder.identifier
            } else {
                let ext = (dragExportFileName(for: item) as NSString).pathExtension
                fileType = UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
            }

            let delegate = DragPlaceholderPromiseDelegate(item: item)
            delegate.connectionID = parent.bookmarkID
            delegate.transferManager = parent.transferManager
            delegate.onDownloadTransferError = parent.onDownloadTransferError
            let provider = NSFilePromiseProvider(fileType: fileType, delegate: delegate)
            objc_setAssociatedObject(
                provider,
                &dragPromiseDelegateAssociationKey,
                delegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return provider
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? [.move, .copy, .link] : .copy
        }

        func tableView(_ tableView: NSTableView, draggingSession _: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
            clearDropFeedbackOnly()
            refreshExternalDragConfiguration()
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt _: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            let draggedPaths = rowIndexes.compactMap { index -> String? in
                guard index >= 0, index < items.count else { return nil }
                return items[index].path
            }

            guard !draggedPaths.isEmpty else { return }
            session.draggingPasteboard.setString(
                draggedPaths.joined(separator: "\n"),
                forType: wiredRemotePathPasteboardType
            )
        }

        private func finderDroppedURLs(from info: NSDraggingInfo) -> [URL] {
            let classes: [AnyClass] = [NSURL.self]
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true
            ]
            return info.draggingPasteboard.readObjects(forClasses: classes, options: options) as? [URL] ?? []
        }

        private func remoteDroppedPaths(from info: NSDraggingInfo) -> [String] {
            let raw = info.draggingPasteboard.string(forType: wiredRemotePathPasteboardType) ?? ""
            return raw
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
        }

        fileprivate func clearDropState() {
            showDropFeedback(nil, highlightColumnBackground: false)
            updateDropTargetRow(nil)
            tableView?.needsDisplay = true
        }

        fileprivate func clearDropFeedbackOnly() {
            showDropFeedback(nil, highlightColumnBackground: false)
        }

        private func refreshExternalDragConfiguration() {
            guard let tableView else { return }
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
            tableView.setDraggingSourceOperationMask([.move, .copy, .link], forLocal: true)
            tableView.registerForDraggedTypes([.fileURL, wiredRemotePathPasteboardType])
        }

        private func updateDropTargetRow(_ row: Int?) {
            guard let tableView else { return }

            let previousRow = activeDropTargetRow
            activeDropTargetRow = row

            if let row {
                tableView.setDropRow(row, dropOperation: .on)
            } else {
                tableView.setDropRow(-1, dropOperation: .above)
            }

            var rowsNeedingDisplay = IndexSet()
            if let previousRow, previousRow >= 0, previousRow < tableView.numberOfRows {
                rowsNeedingDisplay.insert(previousRow)
            }
            if let row, row >= 0, row < tableView.numberOfRows {
                rowsNeedingDisplay.insert(row)
            }
            rowsNeedingDisplay.formUnion(tableView.selectedRowIndexes)

            guard !rowsNeedingDisplay.isEmpty, tableView.numberOfColumns > 0 else { return }
            tableView.reloadData(
                forRowIndexes: rowsNeedingDisplay,
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }

        private func resolvedDropTarget(in tableView: NSTableView, info: NSDraggingInfo, proposedRow row: Int) -> (destination: FileItem, row: Int?, highlightsColumnBackground: Bool)? {
            let localPoint = tableView.convert(info.draggingLocation, from: nil)
            let hoveredRow = tableView.row(at: localPoint)

            if hoveredRow >= 0, hoveredRow < items.count {
                let item = items[hoveredRow]
                if isDirectory(item) {
                    return (item, hoveredRow, false)
                }
                return nil
            }

            if row >= 0, row < items.count {
                let item = items[row]
                if isDirectory(item) {
                    return (item, row, false)
                }
            }

            return (columnDirectory(), nil, true)
        }

        fileprivate func showDropFeedback(_ kind: RemoteDropOperationBadgeKind?, highlightColumnBackground: Bool) {
            guard let scrollView else { return }

            if let highlightView = dropHighlightView {
                highlightView.isHidden = !highlightColumnBackground
            } else if highlightColumnBackground {
                let created = RemoteColumnDropHighlightView(frame: .zero)
                created.translatesAutoresizingMaskIntoConstraints = false
                scrollView.addSubview(created, positioned: .below, relativeTo: tableView)
                NSLayoutConstraint.activate([
                    created.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 6),
                    created.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -6),
                    created.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 6),
                    created.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -6)
                ])
                created.isHidden = false
                dropHighlightView = created
            }

            if kind == nil {
                dropBadgeView?.isHidden = true
                return
            }

            let badgeView: RemoteDropOperationBadgeView
            if let existing = dropBadgeView {
                badgeView = existing
            } else {
                let created = RemoteDropOperationBadgeView(frame: .zero)
                created.translatesAutoresizingMaskIntoConstraints = false
                scrollView.addSubview(created)
                NSLayoutConstraint.activate([
                    created.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
                    created.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12)
                ])
                dropBadgeView = created
                badgeView = created
            }

            badgeView.configure(kind!)
            badgeView.isHidden = false
        }

        private func prefersLinkOperation(_ info: NSDraggingInfo) -> Bool {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            return flags.contains(.command) && flags.contains(.option)
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard let target = resolvedDropTarget(in: tableView, info: info, proposedRow: row) else {
                clearDropState()
                return []
            }
            let destination = target.destination
            let remotePaths = remoteDroppedPaths(from: info)

            if !remotePaths.isEmpty {
                let shouldLink = prefersLinkOperation(info)
                if remotePaths.contains(where: { $0 == destination.path || destination.path.hasPrefix($0 + "/") }) {
                    clearDropState()
                    return []
                }
                if remotePaths.contains(where: { !parent.canDropRemoteItem($0, destination, shouldLink) }) {
                    clearDropState()
                    return []
                }
                updateDropTargetRow(target.row)
                showDropFeedback(shouldLink ? .link : .move, highlightColumnBackground: target.highlightsColumnBackground)
                return shouldLink ? .link : .move
            }

            if !finderDroppedURLs(from: info).isEmpty {
                showDropFeedback(nil, highlightColumnBackground: target.highlightsColumnBackground)
                updateDropTargetRow(target.row)
                return .copy
            }

            clearDropState()
            return []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            defer { clearDropState() }
            guard let target = resolvedDropTarget(in: tableView, info: info, proposedRow: row) else { return false }
            let destination = target.destination

            let remotePaths = remoteDroppedPaths(from: info)
            if !remotePaths.isEmpty {
                let shouldLink = prefersLinkOperation(info)
                guard !remotePaths.contains(where: { !parent.canDropRemoteItem($0, destination, shouldLink) }) else {
                    return false
                }
                for source in remotePaths {
                    Task {
                        do {
                            try await parent.onMoveRemoteItem(source, destination, shouldLink)
                        } catch {
                        }
                    }
                }
                return true
            }

            let urls = finderDroppedURLs(from: info)
            if !urls.isEmpty {
                refreshExternalDragConfiguration()
                DispatchQueue.main.async {
                    self.parent.onUploadURLs(urls, destination)
                }
                return true
            }

            return false
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            var item = menu.addItem(withTitle: NSLocalizedString("Get Info", comment: ""), action: #selector(contextGetInfo), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)

            item = menu.addItem(withTitle: NSLocalizedString("Quick Look", comment: ""), action: #selector(contextQuickLook), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)

            menu.addItem(NSMenuItem.separator())
            item = menu.addItem(withTitle: NSLocalizedString("New Folder", comment: ""), action: #selector(contextNewFolder), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)

            item = menu.addItem(withTitle: NSLocalizedString("Download", comment: ""), action: #selector(contextDownload), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)

            item = menu.addItem(withTitle: NSLocalizedString("Upload…", comment: ""), action: #selector(contextUpload), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)

            menu.addItem(makeLabelSubmenuItem(target: self))

            menu.addItem(NSMenuItem.separator())
            item = menu.addItem(withTitle: NSLocalizedString("Delete", comment: ""), action: #selector(contextDelete), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)

            menu.addItem(NSMenuItem.separator())
            let statusItem = menu.addItem(withTitle: NSLocalizedString("Sync Status: Pair inactive", comment: ""), action: nil, keyEquivalent: "")
            statusItem.tag = SyncContextMenuItemTag.status
            let toggleItem = menu.addItem(withTitle: NSLocalizedString("Activate Sync Pair", comment: ""), action: #selector(contextToggleSyncPair), keyEquivalent: "")
            toggleItem.tag = SyncContextMenuItemTag.toggle
            toggleItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)

            let syncNowItem = menu.addItem(withTitle: NSLocalizedString("Sync Now", comment: ""), action: #selector(contextSyncNow), keyEquivalent: "")
            syncNowItem.tag = SyncContextMenuItemTag.syncNow
            syncNowItem.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise", accessibilityDescription: nil)

            for item in menu.items {
                item.target = self
            }
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let tableView else { return }
            let row = tableView.clickedRow

            if row >= 0 && row < items.count {
                if !tableView.selectedRowIndexes.contains(row) {
                    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }

                let item = items[row]
                if isDirectory(item) {
                    contextDirectoryTarget = item
                } else {
                    contextDirectoryTarget = columnDirectory()
                }
            } else {
                if !tableView.selectedRowIndexes.isEmpty {
                    tableView.deselectAll(nil)
                }
                contextDirectoryTarget = columnDirectory()
            }

            let selected = selectedItems()
            menu.item(withTitle: NSLocalizedString("Quick Look", comment: ""))?.isEnabled = selected.contains(where: { RemoteQuickLookSupport.isPreviewable($0) })
            menu.item(withTitle: NSLocalizedString("Download", comment: ""))?.isEnabled = selected.contains(where: { parent.canDownloadForItem($0) })
            menu.item(withTitle: NSLocalizedString("Delete", comment: ""))?.isEnabled = selected.contains(where: { parent.canDeleteForItem($0) })
            menu.item(withTitle: NSLocalizedString("Upload…", comment: ""))?.isEnabled = parent.canUploadToDirectory(contextDirectoryTarget)
            let canGetSelectedInfo: Bool = {
                guard selected.count == 1, let item = selected.first else { return false }
                return parent.canGetInfoForItem(item)
            }()
            menu.item(withTitle: NSLocalizedString("Get Info", comment: ""))?.isEnabled = canGetSelectedInfo
            let selectedSyncItem: FileItem? = {
                guard selected.count == 1, let item = selected.first, item.type == .sync else { return nil }
                return item
            }()
            let syncState: SyncPairStatusDisplay = selectedSyncItem.map { parent.syncPairStatusForItem($0) } ?? .hidden
            let pairExists = selectedSyncItem.map { parent.syncPairExistsForItem($0) } ?? false
            if let syncStatusItem = menu.item(withTag: SyncContextMenuItemTag.status) {
                switch syncState {
                case .paused:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Paused", comment: "")
                case .connecting:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Connecting…", comment: "")
                case .connected:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Connected", comment: "")
                case .syncing:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Syncing…", comment: "")
                case .reconnecting:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Reconnecting…", comment: "")
                case .error(let message):
                    syncStatusItem.title = "Sync Status: Error\(message.map { " - \($0)" } ?? "")"
                case .inactive:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Pair inactive", comment: "")
                case .checking:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Updating…", comment: "")
                case .hidden:
                    syncStatusItem.title = NSLocalizedString("Sync Status: Pair inactive", comment: "")
                }
                syncStatusItem.isHidden = selectedSyncItem == nil
                syncStatusItem.isEnabled = false
            }
            if let toggleItem = menu.item(withTag: SyncContextMenuItemTag.toggle) {
                if selectedSyncItem == nil {
                    toggleItem.title = NSLocalizedString("Activate Sync Pair", comment: "")
                    toggleItem.isEnabled = false
                } else if syncState == .checking {
                    toggleItem.title = pairExists ? NSLocalizedString("Deactivate Sync Pair", comment: "") : NSLocalizedString("Activate Sync Pair", comment: "")
                    toggleItem.isEnabled = false
                } else if pairExists {
                    toggleItem.title = NSLocalizedString("Deactivate Sync Pair", comment: "")
                    toggleItem.isEnabled = true
                } else {
                    toggleItem.title = NSLocalizedString("Activate Sync Pair", comment: "")
                    toggleItem.isEnabled = true
                }
                toggleItem.isHidden = selectedSyncItem == nil
            }
            menu.item(withTag: SyncContextMenuItemTag.syncNow)?.isHidden = selectedSyncItem == nil
            menu.item(withTag: SyncContextMenuItemTag.syncNow)?.isEnabled = selectedSyncItem != nil && pairExists && syncState != .checking
            menu.item(withTitle: NSLocalizedString("New Folder", comment: ""))?.isEnabled = parent.canCreateFolderInDirectory(contextDirectoryTarget)
            if let labelItem = menu.item(withTag: LabelContextMenuItemTag.submenu) {
                labelItem.isEnabled = parent.canSetLabel && !selectedItems().isEmpty
            }
        }

        private func selectedItems() -> [FileItem] {
            guard let tableView else { return [] }
            return tableView.selectedRowIndexes.compactMap { row in
                guard row >= 0 && row < items.count else { return nil }
                return items[row]
            }
        }

        @objc private func contextQuickLook() {
            presentQuickLook()
        }

        @objc private func contextDownload() {
            let selected = selectedItems().filter { parent.canDownloadForItem($0) }
            guard !selected.isEmpty else { return }
            parent.onRequestDownloadSelection(selected)
        }

        @objc private func contextDelete() {
            let selected = selectedItems().filter { parent.canDeleteForItem($0) }
            guard !selected.isEmpty else { return }
            parent.onRequestDeleteSelection(selected)
        }

        @objc private func contextUpload() {
            guard parent.canUploadToDirectory(contextDirectoryTarget) else { return }
            parent.onRequestUploadInDirectory(contextDirectoryTarget)
        }

        @objc private func contextGetInfo() {
            guard let item = selectedItems().first else { return }
            guard parent.canGetInfoForItem(item) else { return }
            parent.onRequestGetInfo(item)
        }

        @objc private func contextSyncNow() {
            guard let item = selectedItems().first, item.type == .sync else { return }
            parent.onRequestSyncNow(item)
        }

        @objc private func contextToggleSyncPair() {
            guard let item = selectedItems().first, item.type == .sync else { return }
            if parent.syncPairStatusForItem(item) == .checking {
                return
            }
            if parent.syncPairExistsForItem(item) {
                parent.onRequestDeactivateSync(item)
            } else {
                parent.onRequestActivateSync(item)
            }
        }

        @objc private func contextNewFolder() {
            guard parent.canCreateFolderInDirectory(contextDirectoryTarget) else { return }
            parent.onRequestCreateFolder(contextDirectoryTarget)
        }

        @objc func contextSetLabel(_ sender: NSMenuItem) {
            let rawValue = UInt32(sender.tag - LabelContextMenuItemTag.itemBase)
            let label = FileLabelValue(rawValue: rawValue) ?? .none
            let targets = selectedItems()
            guard !targets.isEmpty else { return }
            parent.onRequestSetLabel(targets, label)
        }
    }
}

private extension FileLabelValue {
    var nsColor: NSColor {
        switch self {
        case .none:
            return .secondaryLabelColor
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .blue:
            return .systemBlue
        case .purple:
            return .systemPurple
        case .gray:
            return .systemGray
        }
    }
}
#endif
