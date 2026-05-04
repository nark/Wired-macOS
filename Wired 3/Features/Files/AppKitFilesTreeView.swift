#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ObjectiveC
import WiredSwift

private final class TreeFileLabelDotView: NSView {
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

private final class QuickLookOutlineView: NSOutlineView {
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

fileprivate enum TreeRemoteDropOperationBadgeKind {
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

private final class TreeRemoteDropOperationBadgeView: NSVisualEffectView {
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

    func configure(_ kind: TreeRemoteDropOperationBadgeKind) {
        textField.stringValue = kind.title
        textField.textColor = kind.tintColor
        imageView.contentTintColor = kind.tintColor
        imageView.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title)
    }
}

// swiftlint:disable type_body_length
struct AppKitFilesTreeView: NSViewRepresentable {
    private enum ColumnID {
        static let name = NSUserInterfaceItemIdentifier("TreeColumn")
        static let kind = NSUserInterfaceItemIdentifier("KindColumn")
        static let modified = NSUserInterfaceItemIdentifier("ModifiedColumn")
        static let size = NSUserInterfaceItemIdentifier("SizeColumn")
    }

    let rootPath: String
    let treeChildrenByPath: [String: [FileItem]]
    let expandedPaths: Set<String>
    @Binding var sortColumn: String
    @Binding var sortAscending: Bool
    let connectionID: UUID
    let quickLookConnection: AsyncConnection?
    let transferManager: TransferManager
    let onDownloadTransferError: (FileItem, String) -> Void
    let onUploadURLs: ([URL], FileItem) -> Void
    let onMoveRemoteItem: (_ sourcePath: String, _ destinationDirectory: FileItem, _ link: Bool) async throws -> Void
    @Binding var selectedPaths: Set<String>
    let onSelectionChange: (Set<String>) -> Void
    let onSetDirectoryExpanded: (String, Bool) -> Void
    let onDownloadSingleFile: (FileItem) -> Void
    let onOpenDirectory: (FileItem) -> Void
    let onRequestCreateFolder: () -> Void
    let onRequestUploadInDirectory: (FileItem) -> Void
    let onRequestDeleteSelection: () -> Void
    let onRequestDownloadSelection: () -> Void
    let onRequestGetInfo: (FileItem) -> Void
    let onRequestSyncNow: (FileItem) -> Void
    let onRequestActivateSync: (FileItem) -> Void
    let onRequestDeactivateSync: (FileItem) -> Void
    let syncPairStatusForPath: (String) -> SyncPairStatusDisplay
    let syncPairExistsForPath: (String) -> Bool
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
    let savedScrollOffset: CGPoint
    let onScrollOffsetChange: (CGPoint) -> Void

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
        scrollView.automaticallyAdjustsContentInsets = false

        let outlineView = QuickLookOutlineView()
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .clear
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.rowHeight = 26
        outlineView.usesAutomaticRowHeights = false
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.setDraggingSourceOperationMask([.move, .copy, .link], forLocal: true)
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.registerForDraggedTypes([.fileURL, wiredRemotePathPasteboardType])
        outlineView.doubleAction = #selector(Coordinator.didDoubleClick(_:))
        outlineView.target = context.coordinator
        outlineView.onQuickLook = { [weak coordinator = context.coordinator] in
            coordinator?.presentQuickLook()
        }
        outlineView.onDraggingExited = { [weak coordinator = context.coordinator] in
            coordinator?.clearDropState()
        }
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true

        let column = NSTableColumn(identifier: ColumnID.name)
        column.title = NSLocalizedString("Name", comment: "")
        column.minWidth = 220
        column.width = 420
        column.resizingMask = .autoresizingMask
        column.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let kindColumn = NSTableColumn(identifier: ColumnID.kind)
        kindColumn.title = NSLocalizedString("Kind", comment: "")
        kindColumn.minWidth = 110
        kindColumn.width = 110
        kindColumn.resizingMask = .userResizingMask
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)
        outlineView.addTableColumn(kindColumn)

        let modifiedColumn = NSTableColumn(identifier: ColumnID.modified)
        modifiedColumn.title = NSLocalizedString("Modified", comment: "")
        modifiedColumn.minWidth = 140
        modifiedColumn.width = 140
        modifiedColumn.resizingMask = .userResizingMask
        modifiedColumn.sortDescriptorPrototype = NSSortDescriptor(key: "modified", ascending: false)
        outlineView.addTableColumn(modifiedColumn)

        let sizeColumn = NSTableColumn(identifier: ColumnID.size)
        sizeColumn.title = NSLocalizedString("Size", comment: "")
        sizeColumn.minWidth = 100
        sizeColumn.width = 100
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
        outlineView.addTableColumn(sizeColumn)

        let initialSortDescriptor = sortDescriptor(
            for: sortColumn,
            ascending: sortAscending,
            outlineView: outlineView
        ) ?? column.sortDescriptorPrototype
        outlineView.sortDescriptors = [initialSortDescriptor].compactMap { $0 }

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        let menu = context.coordinator.makeContextMenu()
        menu.delegate = context.coordinator
        outlineView.menu = menu

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView
        context.coordinator.scrollView = scrollView
        context.coordinator.applyHeaderInset()
        context.coordinator.syncFromModel(
            rootPath: rootPath,
            childrenByPath: treeChildrenByPath,
            expandedPaths: expandedPaths,
            selectedPaths: selectedPaths,
            syncPairStatusVersion: syncPairStatusVersion
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        DispatchQueue.main.async {
            context.coordinator.restoreScrollPosition(savedScrollOffset)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyHeaderInset()
        context.coordinator.applySortDescriptorIfNeeded()
        context.coordinator.syncFromModel(
            rootPath: rootPath,
            childrenByPath: treeChildrenByPath,
            expandedPaths: expandedPaths,
            selectedPaths: selectedPaths,
            syncPairStatusVersion: syncPairStatusVersion
        )
    }

    private func sortDescriptor(
        for key: String,
        ascending: Bool,
        outlineView: NSOutlineView
    ) -> NSSortDescriptor? {
        guard let column = outlineView.tableColumns.first(where: { $0.sortDescriptorPrototype?.key == key }) else {
            return nil
        }

        if let prototype = column.sortDescriptorPrototype {
            return NSSortDescriptor(key: prototype.key, ascending: ascending)
        }

        return NSSortDescriptor(key: key, ascending: ascending)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        final class OutlineNode: NSObject {
            let item: FileItem
            var children: [OutlineNode] = []

            init(item: FileItem) {
                self.item = item
            }
        }

        var parent: AppKitFilesTreeView
        weak var outlineView: NSOutlineView?
        weak var scrollView: NSScrollView?
        private let rootNode = OutlineNode(item: FileItem("/", path: "/", type: .directory))
        private var nodesByPath: [String: OutlineNode] = [:]
        private var currentRootPath: String = "/"
        private var isApplyingSelectionFromSwiftUI = false
        private var isApplyingExpandedStateFromSwiftUI = false
        private var suppressDisclosureCallbacks = false
        private var pendingExpansionState: [String: Bool] = [:]
        private var contextDirectoryTarget: FileItem = FileItem("/", path: "/", type: .directory)
        private var contextSyncTarget: FileItem?
        private var clickedRowHadSelection = false
        private var lastChildrenPaths: [String: [String]] = [:]
        private var lastSyncPairStatusVersion: Int = -1
        private var currentChildrenByPath: [String: [FileItem]] = [:]
        private var lastExpandedPaths: Set<String> = ["/"]
        private var lastSelectedPaths: Set<String> = []
        private var activeSortKey: String = "name"
        private var activeSortAscending = true
        private var isRestoringScrollPosition = false
        private weak var dropBadgeView: TreeRemoteDropOperationBadgeView?
        private lazy var quickLookController = FilesQuickLookController(
            connectionID: parent.connectionID,
            sourceFrameProvider: { [weak self] path in
                self?.sourceFrameOnScreen(for: path)
            },
            windowProvider: { [weak self] in
                self?.outlineView?.window
            },
            connectionProvider: { [weak self] in
                self?.parent.quickLookConnection
            }
        )

        init(parent: AppKitFilesTreeView) {
            self.parent = parent
            self.currentRootPath = parent.rootPath
            self.activeSortKey = parent.sortColumn
            self.activeSortAscending = parent.sortAscending
            let normalizedRoot: String = {
                if parent.rootPath == "/" { return "/" }
                let trimmed = parent.rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return trimmed.isEmpty ? "/" : "/" + trimmed
            }()
            let rootName = normalizedRoot == "/" ? "/" : (normalizedRoot as NSString).lastPathComponent
            self.contextDirectoryTarget = FileItem(rootName, path: normalizedRoot, type: .directory)
        }

        func applySortDescriptorIfNeeded() {
            guard let outlineView else { return }
            let desiredKey = parent.sortColumn
            let desiredAscending = parent.sortAscending
            let currentDescriptor = outlineView.sortDescriptors.first
            if currentDescriptor?.key == desiredKey, currentDescriptor?.ascending == desiredAscending {
                activeSortKey = desiredKey
                activeSortAscending = desiredAscending
                return
            }

            if outlineView.tableColumns.contains(where: { $0.sortDescriptorPrototype?.key == desiredKey }) {
                let descriptor = NSSortDescriptor(key: desiredKey, ascending: desiredAscending)
                outlineView.sortDescriptors = [descriptor]
                activeSortKey = desiredKey
                activeSortAscending = desiredAscending
                refreshTree(rootPath: currentRootPath, childrenByPath: currentChildrenByPath)
                applyExpandedState(lastExpandedPaths)
                updateSelection(lastSelectedPaths)
            } else if let fallback = outlineView.tableColumns.first?.sortDescriptorPrototype {
                outlineView.sortDescriptors = [fallback]
                activeSortKey = fallback.key ?? "name"
                activeSortAscending = fallback.ascending
            }
        }

        @objc func handleScrollChange(_ notification: Notification) {
            guard let sv = scrollView else { return }
            if isRestoringScrollPosition { return }
            parent.onScrollOffsetChange(normalizedScrollOffset(from: sv.contentView.bounds.origin))
        }

        func restoreScrollPosition(_ offset: CGPoint) {
            guard let scrollView, let outlineView else { return }

            isRestoringScrollPosition = true
            defer {
                DispatchQueue.main.async { [weak self] in
                    self?.isRestoringScrollPosition = false
                }
            }

            let restoredOffset = denormalizedScrollOffset(from: offset)

            if offset.y <= 0.5 {
                if outlineView.numberOfRows > 0 {
                    outlineView.scrollRowToVisible(0)
                }
                scrollView.contentView.scroll(to: denormalizedScrollOffset(from: .zero))
            } else {
                scrollView.contentView.scroll(to: restoredOffset)
            }

            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func applyHeaderInset() {
            guard let scrollView, let outlineView else { return }
            let headerHeight = outlineView.headerView?.frame.height ?? 0
            scrollView.contentView.contentInsets = NSEdgeInsets(top: headerHeight, left: 0, bottom: 0, right: 0)
        }

        private func normalizedScrollOffset(from rawOffset: CGPoint) -> CGPoint {
            CGPoint(x: rawOffset.x, y: max(0, rawOffset.y + topContentInset))
        }

        private func denormalizedScrollOffset(from normalizedOffset: CGPoint) -> CGPoint {
            CGPoint(x: normalizedOffset.x, y: normalizedOffset.y - topContentInset)
        }

        private var topContentInset: CGFloat {
            scrollView?.contentView.contentInsets.top ?? 0
        }

        private func isDirectory(_ item: FileItem) -> Bool {
            item.type.isDirectoryLike
        }

        private func sortedItems(_ items: [FileItem]) -> [FileItem] {
            items.sorted { lhs, rhs in
                let lhsDir = isDirectory(lhs)
                let rhsDir = isDirectory(rhs)
                if lhsDir != rhsDir { return lhsDir }

                let comparison: ComparisonResult = {
                    switch activeSortKey {
                    case "kind":
                        let lhsKind = lhs.type.description
                        let rhsKind = rhs.type.description
                        let kindOrder = lhsKind.localizedCaseInsensitiveCompare(rhsKind)
                        if kindOrder != ComparisonResult.orderedSame { return kindOrder }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    case "modified":
                        let lhsDate = lhs.modificationDate ?? .distantPast
                        let rhsDate = rhs.modificationDate ?? .distantPast
                        if lhsDate != rhsDate {
                            return lhsDate < rhsDate ? .orderedAscending : .orderedDescending
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    case "size":
                        let lhsSize = sortMetric(for: lhs)
                        let rhsSize = sortMetric(for: rhs)
                        if lhsSize != rhsSize {
                            return lhsSize < rhsSize ? .orderedAscending : .orderedDescending
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    default:
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    }
                }()

                if activeSortAscending {
                    return comparison != .orderedDescending
                } else {
                    return comparison == .orderedDescending
                }
            }
        }

        private func sortMetric(for item: FileItem) -> Int64 {
            if item.type == .file {
                return Int64(item.dataSize + item.rsrcSize)
            }
            if item.type.isDirectoryLike, item.hasDirectoryCount {
                return Int64(item.directoryCount)
            }
            return -1
        }

        private func fileSizeString(_ item: FileItem) -> String {
            if item.type.isDirectoryLike {
                guard item.hasDirectoryCount else { return "-" }
                return item.directoryCount == 1 ? "1 item" : "\(item.directoryCount) items"
            }
            guard item.type == .file else { return "-" }
            let total = Int64(item.dataSize + item.rsrcSize)
            return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }

        private func fileKindString(_ item: FileItem) -> String {
            item.type.description
        }

        private func modifiedDateString(_ item: FileItem) -> String {
            guard let date = item.modificationDate else { return "-" }
            return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        }

        private func childrenSnapshot(for items: [FileItem]) -> [String] {
            items.map { item in
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
        }

        private func ancestorPaths(for path: String) -> [String] {
            var result: [String] = []
            var current = (path as NSString).deletingLastPathComponent
            while !current.isEmpty && current != "/" {
                result.append(current)
                current = (current as NSString).deletingLastPathComponent
            }
            result.append("/")
            return result
        }

        private func ensureExpandedAncestors(in expanded: inout Set<String>) {
            let snapshot = Array(expanded)
            for path in snapshot {
                for ancestor in ancestorPaths(for: path) {
                    expanded.insert(ancestor)
                }
            }
        }

        private func treeDepth(for path: String) -> Int {
            if path == "/" { return 0 }
            return path.split(separator: "/").count
        }

        private func normalizedRemotePath(_ path: String) -> String {
            if path == "/" { return "/" }
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if trimmed.isEmpty { return "/" }
            return "/" + trimmed
        }

        private func directoryItem(for path: String) -> FileItem {
            let normalized = normalizedRemotePath(path)
            let name = normalized == "/" ? "/" : (normalized as NSString).lastPathComponent
            return FileItem(name, path: normalized, type: .directory)
        }

        func refreshTree(rootPath: String, childrenByPath: [String: [FileItem]]) {
            currentChildrenByPath = childrenByPath
            lastChildrenPaths = childrenByPath.mapValues(childrenSnapshot(for:))
            nodesByPath.removeAll()
            currentRootPath = normalizedRemotePath(rootPath)

            func node(for item: FileItem) -> OutlineNode {
                if let existing = nodesByPath[item.path] { return existing }
                let created = OutlineNode(item: item)
                nodesByPath[item.path] = created
                return created
            }

            func buildChildren(parentPath: String, visiting: inout Set<String>) -> [OutlineNode] {
                guard !visiting.contains(parentPath) else { return [] }
                visiting.insert(parentPath)
                defer { visiting.remove(parentPath) }

                let children = sortedItems(childrenByPath[parentPath] ?? [])
                return children.map { childItem in
                    let childNode = node(for: childItem)
                    if isDirectory(childItem), childrenByPath[childItem.path] != nil {
                        childNode.children = buildChildren(parentPath: childItem.path, visiting: &visiting)
                    } else {
                        childNode.children = []
                    }
                    return childNode
                }
            }

            var visiting: Set<String> = []
            rootNode.children = buildChildren(parentPath: currentRootPath, visiting: &visiting)
            outlineView?.reloadData()
        }

        func syncFromModel(
            rootPath: String,
            childrenByPath: [String: [FileItem]],
            expandedPaths: Set<String>,
            selectedPaths: Set<String>,
            syncPairStatusVersion: Int
        ) {
            for (path, desiredExpanded) in pendingExpansionState {
                let modelExpanded = expandedPaths.contains(path)
                if modelExpanded == desiredExpanded {
                    pendingExpansionState.removeValue(forKey: path)
                }
            }

            var effectiveExpandedPaths = expandedPaths
            for (path, desiredExpanded) in pendingExpansionState {
                if desiredExpanded {
                    effectiveExpandedPaths.insert(path)
                } else {
                    effectiveExpandedPaths.remove(path)
                }
            }
            ensureExpandedAncestors(in: &effectiveExpandedPaths)

            suppressDisclosureCallbacks = true
            defer { suppressDisclosureCallbacks = false }

            let newRoot = normalizedRemotePath(rootPath)
            let treeChanged = newRoot != currentRootPath || treeStructureDidChange(childrenByPath)
            let syncStatusChanged = syncPairStatusVersion != lastSyncPairStatusVersion
            lastExpandedPaths = effectiveExpandedPaths
            lastSelectedPaths = selectedPaths
            if treeChanged {
                refreshTree(rootPath: rootPath, childrenByPath: childrenByPath)
            } else if syncStatusChanged {
                refreshSyncIndicators()
            }
            lastSyncPairStatusVersion = syncPairStatusVersion
            applyExpandedState(effectiveExpandedPaths)
            updateSelection(selectedPaths)
        }

        private func treeStructureDidChange(_ newChildren: [String: [FileItem]]) -> Bool {
            guard newChildren.count == lastChildrenPaths.count else { return true }
            for (key, items) in newChildren {
                guard let cached = lastChildrenPaths[key], cached == childrenSnapshot(for: items) else { return true }
            }
            return false
        }

        private func refreshSyncIndicators() {
            guard let outlineView else { return }
            for node in nodesByPath.values where node.item.type == .sync {
                outlineView.reloadItem(node, reloadChildren: false)
            }
        }

        func applyExpandedState(_ expandedPaths: Set<String>) {
            guard let outlineView else { return }
            isApplyingExpandedStateFromSwiftUI = true
            defer { isApplyingExpandedStateFromSwiftUI = false }

            let expandableNodes = nodesByPath.values
                .filter { isDirectory($0.item) }
                .sorted {
                    let lhsDepth = treeDepth(for: $0.item.path)
                    let rhsDepth = treeDepth(for: $1.item.path)
                    if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
                    return $0.item.path < $1.item.path
                }

            for node in expandableNodes {
                let path = node.item.path
                if expandedPaths.contains(path), !outlineView.isItemExpanded(node) {
                    outlineView.expandItem(node, expandChildren: false)
                }
            }

            for node in expandableNodes.reversed() {
                let path = node.item.path
                if !expandedPaths.contains(path), outlineView.isItemExpanded(node) {
                    outlineView.collapseItem(node, collapseChildren: false)
                }
            }
        }

        func updateSelection(_ selectedPaths: Set<String>) {
            guard let outlineView else { return }
            var indexSet = IndexSet()
            for path in selectedPaths {
                guard let node = nodesByPath[path] else { continue }
                let row = outlineView.row(forItem: node)
                if row >= 0 {
                    indexSet.insert(row)
                }
            }
            if outlineView.selectedRowIndexes != indexSet {
                isApplyingSelectionFromSwiftUI = true
                outlineView.selectRowIndexes(indexSet, byExtendingSelection: false)
                isApplyingSelectionFromSwiftUI = false
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            let node = (item as? OutlineNode) ?? rootNode
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            let node = (item as? OutlineNode) ?? rootNode
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? OutlineNode else { return false }
            return isDirectory(node.item)
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? OutlineNode else { return nil }
            let item = node.item
            let columnID = tableColumn?.identifier ?? ColumnID.name

            if columnID == ColumnID.size {
                let id = NSUserInterfaceItemIdentifier("TreeSizeCell")
                let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                    let cell = NSTableCellView()
                    cell.identifier = id
                    let tf = NSTextField(labelWithString: "")
                    tf.translatesAutoresizingMaskIntoConstraints = false
                    tf.alignment = .right
                    tf.textColor = .secondaryLabelColor
                    tf.lineBreakMode = .byClipping
                    cell.addSubview(tf)
                    cell.textField = tf
                    NSLayoutConstraint.activate([
                        tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                        tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                        tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                    return cell
                }()
                cell.textField?.stringValue = fileSizeString(item)
                return cell
            }

            if columnID == ColumnID.kind {
                let id = NSUserInterfaceItemIdentifier("TreeKindCell")
                let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                    let cell = NSTableCellView()
                    cell.identifier = id
                    let tf = NSTextField(labelWithString: "")
                    tf.translatesAutoresizingMaskIntoConstraints = false
                    tf.textColor = .secondaryLabelColor
                    tf.lineBreakMode = .byTruncatingTail
                    cell.addSubview(tf)
                    cell.textField = tf
                    NSLayoutConstraint.activate([
                        tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                        tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                        tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                    return cell
                }()
                cell.textField?.stringValue = fileKindString(item)
                return cell
            }

            if columnID == ColumnID.modified {
                let id = NSUserInterfaceItemIdentifier("TreeModifiedCell")
                let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                    let cell = NSTableCellView()
                    cell.identifier = id
                    let tf = NSTextField(labelWithString: "")
                    tf.translatesAutoresizingMaskIntoConstraints = false
                    tf.textColor = .secondaryLabelColor
                    tf.lineBreakMode = .byTruncatingTail
                    cell.addSubview(tf)
                    cell.textField = tf
                    NSLayoutConstraint.activate([
                        tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                        tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                        tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                    return cell
                }()
                cell.textField?.stringValue = modifiedDateString(item)
                return cell
            }

            let id = NSUserInterfaceItemIdentifier("TreeCell")
            let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                let cell = NSTableCellView()
                cell.identifier = id
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.imageScaling = .scaleProportionallyUpOrDown
                cell.imageView = icon

                let labelDot = TreeFileLabelDotView(frame: .zero)
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

                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    icon.heightAnchor.constraint(equalToConstant: 16),
                    tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    labelDot.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -32),
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
            let labelDot = cell.subviews.compactMap { $0 as? TreeFileLabelDotView }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("FileLabelDot") })
            labelDot?.configure(label: item.label)

            let statusIcon = cell.subviews.compactMap { $0 as? NSImageView }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("SyncStatusIcon") })
            let statusSpinner = cell.subviews.compactMap { $0 as? NSProgressIndicator }
                .first(where: { $0.identifier == NSUserInterfaceItemIdentifier("SyncStatusSpinner") })
            let syncStatus: SyncPairStatusDisplay = item.type == .sync
                ? parent.syncPairStatusForPath(item.path)
                : .hidden
            switch syncStatus {
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
                cell.toolTip = syncStatus == .reconnecting ? NSLocalizedString("Sync reconnecting", comment: "") : NSLocalizedString("Sync in progress", comment: "")
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

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            let nextDescriptor = outlineView.sortDescriptors.first
            activeSortKey = nextDescriptor?.key ?? "name"
            activeSortAscending = nextDescriptor?.ascending ?? true
            parent.sortColumn = activeSortKey
            parent.sortAscending = activeSortAscending
            refreshTree(rootPath: currentRootPath, childrenByPath: currentChildrenByPath)
            applyExpandedState(lastExpandedPaths)
            updateSelection(lastSelectedPaths)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            if isApplyingSelectionFromSwiftUI { return }
            guard let outlineView else { return }
            var paths = Set<String>()
            for index in outlineView.selectedRowIndexes {
                guard index >= 0,
                      let node = outlineView.item(atRow: index) as? OutlineNode else { continue }
                paths.insert(node.item.path)
            }
            parent.selectedPaths = paths
            parent.onSelectionChange(paths)
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            if isApplyingExpandedStateFromSwiftUI || suppressDisclosureCallbacks { return }
            guard let node = notification.userInfo?["NSObject"] as? OutlineNode else { return }
            pendingExpansionState[node.item.path] = true
            for ancestor in ancestorPaths(for: node.item.path) {
                pendingExpansionState[ancestor] = true
            }
            DispatchQueue.main.async {
                self.parent.onSetDirectoryExpanded(node.item.path, true)
            }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            if isApplyingExpandedStateFromSwiftUI || suppressDisclosureCallbacks { return }
            guard let node = notification.userInfo?["NSObject"] as? OutlineNode else { return }
            pendingExpansionState[node.item.path] = false
            let prefix = node.item.path == "/" ? "/" : node.item.path + "/"
            for (key, _) in pendingExpansionState where key.hasPrefix(prefix) {
                pendingExpansionState[key] = false
            }
            DispatchQueue.main.async {
                self.parent.onSetDirectoryExpanded(node.item.path, false)
            }
        }

        @objc
        func didDoubleClick(_ sender: Any?) {
            guard let outlineView else { return }
            let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
            guard row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
            let item = node.item
            let isDir = isDirectory(item)
            if isDir {
                parent.onOpenDirectory(item)
            } else if parent.canDownloadForItem(item) {
                parent.onDownloadSingleFile(item)
            }
        }

        func presentQuickLook() {
            let orderedItems = visibleItemsInDisplayOrder()
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

        private func visibleItemsInDisplayOrder() -> [FileItem] {
            guard let outlineView else { return [] }
            return (0..<outlineView.numberOfRows).compactMap { row in
                (outlineView.item(atRow: row) as? OutlineNode)?.item
            }
        }

        private func primarySelectionPath() -> String? {
            guard let outlineView else { return nil }
            let selectedRows = outlineView.selectedRowIndexes
            if outlineView.clickedRow >= 0,
               selectedRows.contains(outlineView.clickedRow),
               let node = outlineView.item(atRow: outlineView.clickedRow) as? OutlineNode {
                return node.item.path
            }
            if let first = selectedRows.first,
               let node = outlineView.item(atRow: first) as? OutlineNode {
                return node.item.path
            }
            return nil
        }

        private func sourceFrameOnScreen(for path: String) -> NSRect? {
            guard let outlineView,
                  let node = nodesByPath[path] else { return nil }
            let row = outlineView.row(forItem: node)
            guard row >= 0 else { return nil }
            let rowRect = outlineView.rect(ofRow: row)
            guard !rowRect.isEmpty else { return nil }
            let rectInWindow = outlineView.convert(rowRect, to: nil)
            return outlineView.window?.convertToScreen(rectInWindow)
        }

        private func selectedItems() -> [FileItem] {
            guard let outlineView else { return [] }
            let selectedRows = outlineView.selectedRowIndexes.compactMap { row -> Int? in
                row >= 0 ? row : nil
            }
            return selectedRows.compactMap { row -> FileItem? in
                (outlineView.item(atRow: row) as? OutlineNode)?.item
            }
        }

        private func prefersLinkOperation(_ info: NSDraggingInfo) -> Bool {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            return flags.contains(.command) && flags.contains(.option)
        }

        private func remoteDroppedPaths(from info: NSDraggingInfo) -> [String] {
            let raw = info.draggingPasteboard.string(forType: wiredRemotePathPasteboardType) ?? ""
            return raw
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
        }

        fileprivate func clearDropState() {
            showDropBadge(nil)
            outlineView?.setDropItem(nil, dropChildIndex: -1)
            outlineView?.needsDisplay = true
        }

        fileprivate func clearDropFeedbackOnly() {
            showDropBadge(nil)
        }

        private func refreshExternalDragConfiguration() {
            guard let outlineView else { return }
            outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
            outlineView.setDraggingSourceOperationMask([.move, .copy, .link], forLocal: true)
            outlineView.registerForDraggedTypes([.fileURL, wiredRemotePathPasteboardType])
        }

        func outlineView(_ outlineView: NSOutlineView, writeItems items: [Any], to _: NSPasteboard) -> Bool {
            let remotePaths = items.compactMap { ($0 as? OutlineNode)?.item.path }
            return !remotePaths.isEmpty
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem itemRef: Any) -> NSPasteboardWriting? {
            guard let node = itemRef as? OutlineNode else { return nil }
            let item = node.item
            let isDir = isDirectory(item)
            let fileType: String
            if isDir {
                fileType = UTType.folder.identifier
            } else {
                let ext = (dragExportFileName(for: item) as NSString).pathExtension
                fileType = UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
            }

            let delegate = DragPlaceholderPromiseDelegate(item: item)
            delegate.connectionID = parent.connectionID
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

        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? [.move, .copy, .link] : .copy
        }

        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt _: NSPoint, forItems draggedItems: [Any]) {
            let draggedPaths = draggedItems.compactMap { itemRef -> String? in
                (itemRef as? OutlineNode)?.item.path
            }

            guard !draggedPaths.isEmpty else { return }
            session.draggingPasteboard.setString(
                draggedPaths.joined(separator: "\n"),
                forType: wiredRemotePathPasteboardType
            )
        }

        func outlineView(_ outlineView: NSOutlineView, draggingSession _: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
            clearDropFeedbackOnly()
            refreshExternalDragConfiguration()
        }

        private func finderDroppedURLs(from info: NSDraggingInfo) -> [URL] {
            let classes: [AnyClass] = [NSURL.self]
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true
            ]
            return info.draggingPasteboard.readObjects(forClasses: classes, options: options) as? [URL] ?? []
        }

        private func dropDestination(for itemRef: Any?) -> FileItem? {
            guard let node = itemRef as? OutlineNode else {
                return directoryItem(for: currentRootPath)
            }

            let item = node.item
            guard isDirectory(item) else { return nil }
            return item
        }

        fileprivate func showDropBadge(_ kind: TreeRemoteDropOperationBadgeKind?) {
            guard let scrollView else { return }

            if kind == nil {
                dropBadgeView?.isHidden = true
                return
            }

            let badgeView: TreeRemoteDropOperationBadgeView
            if let existing = dropBadgeView {
                badgeView = existing
            } else {
                let created = TreeRemoteDropOperationBadgeView(frame: .zero)
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

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            let remotePaths = remoteDroppedPaths(from: info)
            guard let destination = dropDestination(for: item) else { return [] }

            if !remotePaths.isEmpty {
                if remotePaths.contains(where: { $0 == destination.path || destination.path.hasPrefix($0 + "/") }) {
                    clearDropState()
                    return []
                }

                if item == nil || destination.path == currentRootPath {
                    outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
                } else {
                    outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
                }

                let shouldLink = prefersLinkOperation(info)
                if remotePaths.contains(where: { !parent.canDropRemoteItem($0, destination, shouldLink) }) {
                    clearDropState()
                    return []
                }
                showDropBadge(shouldLink ? .link : .move)
                return shouldLink ? .link : .move
            }

            let urls = finderDroppedURLs(from: info)
            guard !urls.isEmpty else {
                clearDropState()
                return []
            }

            if item == nil || destination.path == currentRootPath {
                outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
            } else {
                outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            }
            showDropBadge(nil)
            return .copy
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            defer { clearDropState() }
            guard let destination = dropDestination(for: item) else { return false }

            let remotePaths = remoteDroppedPaths(from: info)
            if !remotePaths.isEmpty {
                let shouldLink = prefersLinkOperation(info)
                guard !remotePaths.contains(where: { !parent.canDropRemoteItem($0, destination, shouldLink) }) else {
                    return false
                }
                for source in remotePaths {
                    Task {
                        do {
                            try await self.parent.onMoveRemoteItem(source, destination, shouldLink)
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
            guard let outlineView else { return }
            let point = outlineView.convert(outlineView.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
            let row = outlineView.row(at: point)
            let hasSelectionBefore = !outlineView.selectedRowIndexes.isEmpty

            if row >= 0 {
                clickedRowHadSelection = outlineView.selectedRowIndexes.contains(row)
                if !clickedRowHadSelection {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }

                if let node = outlineView.item(atRow: row) as? OutlineNode {
                    let item = node.item
                    if isDirectory(item) {
                        contextDirectoryTarget = item
                    } else {
                        let parentPath = item.path.stringByDeletingLastPathComponent
                        contextDirectoryTarget = FileItem(parentPath.lastPathComponent, path: parentPath, type: .directory)
                    }
                } else {
                    contextDirectoryTarget = directoryItem(for: currentRootPath)
                }
            } else {
                clickedRowHadSelection = false
                if hasSelectionBefore {
                    outlineView.deselectAll(nil)
                }
                contextDirectoryTarget = directoryItem(for: currentRootPath)
            }

            let selectedRows = outlineView.selectedRowIndexes.compactMap { row -> Int? in
                row >= 0 ? row : nil
            }
            let selectedItems = selectedRows.compactMap { row -> FileItem? in
                (outlineView.item(atRow: row) as? OutlineNode)?.item
            }
            if let quickLookItem = menu.item(withTitle: NSLocalizedString("Quick Look", comment: "")) {
                quickLookItem.isEnabled = selectedItems.contains(where: { RemoteQuickLookSupport.isPreviewable($0) })
            }
            if let downloadItem = menu.item(withTitle: NSLocalizedString("Download", comment: "")) {
                downloadItem.isEnabled = selectedItems.contains(where: { parent.canDownloadForItem($0) })
            }
            if let deleteItem = menu.item(withTitle: NSLocalizedString("Delete", comment: "")) {
                deleteItem.isEnabled = selectedItems.contains(where: { parent.canDeleteForItem($0) })
            }
            if let uploadItem = menu.item(withTitle: NSLocalizedString("Upload…", comment: "")) {
                uploadItem.isEnabled = parent.canUploadToDirectory(contextDirectoryTarget)
            }
            if let infoItem = menu.item(withTitle: NSLocalizedString("Get Info", comment: "")) {
                let canGetSelectedInfo: Bool = {
                    guard selectedItems.count == 1, let item = selectedItems.first else { return false }
                    return parent.canGetInfoForItem(item)
                }()
                infoItem.isEnabled = canGetSelectedInfo
            }
            let selectedSyncItem: FileItem? = {
                guard selectedItems.count == 1, let item = selectedItems.first, item.type == .sync else { return nil }
                return item
            }()
            contextSyncTarget = selectedSyncItem
            let syncState: SyncPairStatusDisplay = selectedSyncItem.map { parent.syncPairStatusForPath($0.path) } ?? .hidden
            let pairExists = selectedSyncItem.map { parent.syncPairExistsForPath($0.path) } ?? false

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
            if let syncItem = menu.item(withTag: SyncContextMenuItemTag.syncNow) {
                let canSyncNow = selectedSyncItem != nil && pairExists && syncState != .checking
                syncItem.isHidden = selectedSyncItem == nil
                syncItem.isEnabled = canSyncNow
            }
            if let newFolderItem = menu.item(withTitle: NSLocalizedString("New Folder", comment: "")) {
                newFolderItem.isEnabled = parent.canCreateFolderInDirectory(contextDirectoryTarget)
            }
            if let labelItem = menu.item(withTag: LabelContextMenuItemTag.submenu) {
                labelItem.isEnabled = parent.canSetLabel && !selectedItems.isEmpty
            }
        }

        @objc private func contextQuickLook() { presentQuickLook() }
        @objc private func contextDownload() { parent.onRequestDownloadSelection() }
        @objc private func contextDelete() { parent.onRequestDeleteSelection() }
        @objc private func contextUpload() {
            guard parent.canUploadToDirectory(contextDirectoryTarget) else { return }
            parent.onRequestUploadInDirectory(contextDirectoryTarget)
        }
        @objc private func contextGetInfo() {
            guard let item = contextSyncTarget ?? selectedItem() else { return }
            guard parent.canGetInfoForItem(item) else { return }
            parent.onRequestGetInfo(item)
        }
        @objc private func contextSyncNow() {
            guard let item = contextSyncTarget else { return }
            parent.onRequestSyncNow(item)
        }
        @objc private func contextToggleSyncPair() {
            guard let item = contextSyncTarget, item.type == .sync else { return }
            if parent.syncPairStatusForPath(item.path) == .checking {
                return
            }
            if parent.syncPairExistsForPath(item.path) {
                parent.onRequestDeactivateSync(item)
            } else {
                parent.onRequestActivateSync(item)
            }
        }
        private func selectedItem() -> FileItem? {
            let items = selectedItems()
            guard items.count == 1 else { return nil }
            return items.first
        }
        @objc private func contextNewFolder() {
            guard parent.canCreateFolderInDirectory(contextDirectoryTarget) else { return }
            parent.onRequestCreateFolder()
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
// swiftlint:enable type_body_length
#endif
