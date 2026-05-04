import AppKit
import ObjectiveC
import WiredSwift

var dragPromiseDelegateAssociationKey: UInt8 = 0

final class FinderDropSecurityScopeBroker {
    static let shared = FinderDropSecurityScopeBroker()

    private let lock = NSLock()
    private var scopedURLs: [UUID: [URL]] = [:]

    private init() {}

    @discardableResult
    func retainScope(for transferID: UUID, at url: URL) -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        guard didAccess else { return false }

        lock.lock()
        var urls = scopedURLs[transferID] ?? []
        if !urls.contains(where: { $0.path == url.path }) {
            urls.append(url)
        }
        scopedURLs[transferID] = urls
        lock.unlock()
        return true
    }

    func releaseScope(for transferID: UUID) {
        lock.lock()
        let urls = scopedURLs.removeValue(forKey: transferID) ?? []
        lock.unlock()
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

final class DragPlaceholderPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let item: FileItem
    private let isDirectory: Bool
    private let fileName: String
    private let partialName: String
    var connectionID: UUID?
    weak var transferManager: TransferManager?
    var onDownloadTransferError: ((FileItem, String) -> Void)?
    private var didStartTransfer = false

    @MainActor
    private func askOverwrite(path: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("File Already Exists", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Do you want to overwrite \"%@\"?", comment: ""), path)
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Overwrite", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func log(_ message: String) {
        NSLog("[WiredTreeDrag] %@", message)
    }

    init(item: FileItem) {
        self.item = item
        self.isDirectory = item.type.isDirectoryLike
        self.fileName = dragExportFileName(for: item)
        self.partialName = fileName + ".\(Wired.transfersFileExtension)"
        super.init()
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        isDirectory ? fileName : partialName
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo destinationURL: URL, completionHandler: @escaping (Error?) -> Void) {
        if didStartTransfer {
            completionHandler(nil)
            return
        }
        didStartTransfer = true

        let fm = FileManager.default

        // For directories, Finder may rename the destination to avoid a conflict
        // (e.g. "test" → "test 2"). Detect this so we can redirect back to the
        // original name and let queueDownload show the overwrite prompt instead.
        let finderRenamed = isDirectory && destinationURL.lastPathComponent != fileName
        let targetURL: URL
        if isDirectory {
            if finderRenamed {
                // Clean up the renamed placeholder Finder expects us to fill.
                if fm.fileExists(atPath: destinationURL.path) {
                    try? fm.removeItem(at: destinationURL)
                }
                // Redirect to the original (conflicting) path.
                targetURL = destinationURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(fileName, isDirectory: true)
                log("writePromiseTo start path=\(targetURL.path) (redirected from \(destinationURL.lastPathComponent))")
            } else {
                targetURL = destinationURL
                log("writePromiseTo start path=\(targetURL.path)")
            }
        } else {
            targetURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(partialName, isDirectory: false)
            log("writePromiseTo start path=\(targetURL.path)")
        }

        do {
            // For directories without a Finder rename, create the placeholder folder
            // required by NSFilePromiseProvider.
            if isDirectory && !finderRenamed {
                if fm.fileExists(atPath: targetURL.path) {
                    try fm.removeItem(at: targetURL)
                }
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            }
            log("placeholder ready path=\(targetURL.path) finderRenamed=\(finderRenamed)")

            let completionLock = NSLock()
            var terminalError: Error?
            let done = DispatchSemaphore(value: 0)

            if let connectionID, let transferManager {
                Task { @MainActor in
                    let startedTransfer: Transfer?
                    // When we created the placeholder ourselves (no Finder rename),
                    // skip the overwrite check — it would be a false positive.
                    // When Finder renamed (original exists), let the normal check run.
                    let skipOverwriteCheck = self.isDirectory && !finderRenamed
                    switch transferManager.queueDownload(item, to: targetURL.path, with: connectionID, overwriteExistingFile: skipOverwriteCheck) {
                    case let .started(transfer), let .resumed(transfer):
                        startedTransfer = transfer
                    case let .needsOverwrite(destination):
                        if self.askOverwrite(path: destination) {
                            switch transferManager.queueDownload(item, to: targetURL.path, with: connectionID, overwriteExistingFile: true) {
                            case let .started(transfer), let .resumed(transfer):
                                startedTransfer = transfer
                            default:
                                startedTransfer = nil
                            }
                        } else {
                            startedTransfer = nil
                        }
                    case .failed:
                        startedTransfer = nil
                    }

                    guard let transfer = startedTransfer else {
                        self.log("downloadTransfer returned nil path=\(targetURL.path)")
                        if self.isDirectory {
                            completionHandler(NSError(
                                domain: "Wired.DragAndDrop",
                                code: 13,
                                userInfo: [NSLocalizedDescriptionKey: "Unable to start folder download transfer."]
                            ))
                        } else {
                            completionLock.withLock {
                                terminalError = NSError(
                                    domain: "Wired.DragAndDrop",
                                    code: 13,
                                    userInfo: [NSLocalizedDescriptionKey: "Unable to start download transfer."]
                                )
                            }
                            done.signal()
                        }
                        return
                    }

                    if !self.isDirectory && !fm.fileExists(atPath: targetURL.path) {
                        guard fm.createFile(atPath: targetURL.path, contents: nil, attributes: nil) else {
                            completionLock.withLock {
                                terminalError = NSError(
                                    domain: "Wired.DragAndDrop",
                                    code: 12,
                                    userInfo: [NSLocalizedDescriptionKey: "Unable to create placeholder file at destination."]
                                )
                            }
                            done.signal()
                            return
                        }
                    }

                    let primaryScope = FinderDropSecurityScopeBroker.shared.retainScope(for: transfer.id, at: targetURL)
                    let parentURL = targetURL.deletingLastPathComponent()
                    let parentScope = FinderDropSecurityScopeBroker.shared.retainScope(for: transfer.id, at: parentURL)
                    self.log("transfer started id=\(transfer.id) scopeTarget=\(targetURL.path) ok=\(primaryScope) scopeParent=\(parentURL.path) ok=\(parentScope)")
                    transferManager.onTransferTerminal(id: transfer.id) { transfer in
                        FinderDropSecurityScopeBroker.shared.releaseScope(for: transfer.id)
                        if self.isDirectory {
                            return
                        }
                        if transfer.state != .finished {
                            let message = transfer.error.isEmpty
                                ? "Transfer ended with state \(transfer.state.rawValue)."
                                : transfer.error
                            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.onDownloadTransferError?(self.item, message)
                            }
                            completionLock.lock()
                            terminalError = NSError(
                                domain: "Wired.DragAndDrop",
                                code: 14,
                                userInfo: [NSLocalizedDescriptionKey: message]
                            )
                            completionLock.unlock()
                        }
                        done.signal()
                    }

                    if self.isDirectory {
                        completionHandler(nil)
                    }
                }
            } else {
                if isDirectory {
                    completionHandler(NSError(
                        domain: "Wired.DragAndDrop",
                        code: 15,
                        userInfo: [NSLocalizedDescriptionKey: "Missing connection context for folder transfer."]
                    ))
                } else {
                    completionLock.lock()
                    terminalError = NSError(
                        domain: "Wired.DragAndDrop",
                        code: 15,
                        userInfo: [NSLocalizedDescriptionKey: "Missing connection context for transfer."]
                    )
                    completionLock.unlock()
                    done.signal()
                }
            }

            if isDirectory {
                return
            }

            _ = done.wait(timeout: .distantFuture)
            completionLock.lock()
            let error = terminalError
            completionLock.unlock()
            completionHandler(error)
        } catch {
            log("writePromiseTo error path=\(targetURL.path) err=\(error.localizedDescription)")
            completionHandler(error)
        }
    }
}
