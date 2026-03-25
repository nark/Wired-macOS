import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    /// Initializes a SwiftUI `Image` from data.
    init?(data: Data) {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            self.init(uiImage: uiImage)
        } else {
            return nil
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            self.init(nsImage: nsImage)
        } else {
            return nil
        }
        #else
        return nil
        #endif
    }
}


enum AppImageCodec {

    static func image(fromBase64 base64: String) -> Image? {
        guard
            let data = Data(base64Encoded: base64),
            let platformImage = platformImage(from: data)
        else { return nil }

        #if os(iOS)
        return Image(uiImage: platformImage)
        #else
        return Image(nsImage: platformImage)
        #endif
    }

    static func base64(from image: ImagePlatform) -> String? {
        imageData(from: image)?.base64EncodedString()
    }

    // MARK: - Platform

    #if os(iOS)
    typealias ImagePlatform = UIImage

    static func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }

    static func imageData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.85)
    }
    #else
    typealias ImagePlatform = NSImage

    static func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }

    static func imageData(from image: NSImage) -> Data? {
        image.tiffRepresentation
    }
    #endif
}

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

extension PlatformImage {

    func resized(to size: CGSize) -> PlatformImage {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        #else
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1
        )
        newImage.unlockFocus()
        return newImage
        #endif
    }
}
