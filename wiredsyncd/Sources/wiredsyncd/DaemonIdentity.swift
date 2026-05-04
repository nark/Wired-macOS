import Foundation
import AppKit

enum DaemonIdentity {
    static func nick(forRemotePath remotePath: String) -> String {
        let trimmed = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n"))
        guard !trimmed.isEmpty else { return kDaemonNick }
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? kDaemonNick : last
    }

    private static let iconLock = NSLock()
    private static var cachedIcon: String?

    static func folderIconBase64() -> String {
        iconLock.lock()
        defer { iconLock.unlock() }
        if let cached = cachedIcon { return cached }
        let encoded = renderFolderIcon() ?? ""
        cachedIcon = encoded
        return encoded
    }

    private static func renderFolderIcon() -> String? {
        let size = NSSize(width: 32, height: 32)
        let folder = NSWorkspace.shared.icon(for: .folder)
        folder.size = size

        let image = NSImage(size: size)
        image.lockFocus()
        folder.draw(in: NSRect(origin: .zero, size: size))

        if let badge = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                               accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            let sized = badge.withSymbolConfiguration(config) ?? badge
            let badgeSize = NSSize(width: 18, height: 18)
            let origin = NSPoint(x: size.width - badgeSize.width - 1, y: 1)

            NSColor.white.setFill()
            let bgPath = NSBezierPath(ovalIn: NSRect(origin: origin, size: badgeSize).insetBy(dx: -1, dy: -1))
            bgPath.fill()

            sized.draw(in: NSRect(origin: origin, size: badgeSize),
                       from: .zero,
                       operation: .sourceOver,
                       fraction: 1.0)
        }

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png.base64EncodedString()
    }
}
