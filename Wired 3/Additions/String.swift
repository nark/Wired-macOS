//
//  String.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 03/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import Foundation
import SwiftUI

extension String {
    private static let markdownURLPattern = try? NSRegularExpression(
        pattern: "!?\\[[^\\]]*\\]\\((https?://[^\\s\\)]+)\\)",
        options: [.caseInsensitive]
    )

    func replacingEmoticons(using map: [String: String]) -> String {
        var result = self
        for (key, value) in map {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    func attributedWithDetectedLinks(
        linkColor: Color? = nil,
        underlineLinks: Bool = true
    ) -> AttributedString {
        var attributed = AttributedString(self)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let fullRange = NSRange(self.startIndex..<self.endIndex, in: self)

        detector?.matches(in: self, options: [], range: fullRange).forEach { match in
            guard let url = match.url else { return }
            guard let range = Range(match.range, in: self) else { return }
            guard
                let lower = AttributedString.Index(range.lowerBound, within: attributed),
                let upper = AttributedString.Index(range.upperBound, within: attributed)
            else {
                return
            }

            let linkRange = lower..<upper
            attributed[linkRange].link = url
            if let linkColor {
                attributed[linkRange].foregroundColor = linkColor
            }
            if underlineLinks {
                attributed[linkRange].underlineStyle = .single
            }
        }

        return attributed
    }

    func attributedWithMarkdownAndDetectedLinks(
        linkColor: Color? = nil,
        underlineLinks: Bool = true
    ) -> AttributedString {
        let markdownOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        var attributed = (try? AttributedString(markdown: self, options: markdownOptions))
            ?? AttributedString(self)

        let renderedString = String(attributed.characters)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let fullRange = NSRange(renderedString.startIndex..<renderedString.endIndex, in: renderedString)

        detector?.matches(in: renderedString, options: [], range: fullRange).forEach { match in
            guard let url = match.url else { return }
            guard let range = Range(match.range, in: renderedString) else { return }
            guard
                let lower = AttributedString.Index(range.lowerBound, within: attributed),
                let upper = AttributedString.Index(range.upperBound, within: attributed)
            else {
                return
            }

            let linkRange = lower..<upper
            attributed[linkRange].link = url
            if let linkColor {
                attributed[linkRange].foregroundColor = linkColor
            }
            if underlineLinks {
                attributed[linkRange].underlineStyle = .single
            }
        }

        return attributed
    }

    func detectedURLs() -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let fullRange = NSRange(self.startIndex..<self.endIndex, in: self)
        detector?.matches(in: self, options: [], range: fullRange).forEach { match in
            guard let url = match.url else { return }
            let key = url.absoluteString.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            urls.append(url)
        }

        if let markdownURLPattern = Self.markdownURLPattern {
            markdownURLPattern.matches(in: self, options: [], range: fullRange).forEach { match in
                guard match.numberOfRanges > 1 else { return }
                guard let range = Range(match.range(at: 1), in: self) else { return }
                let raw = String(self[range])
                guard let url = URL(string: raw) else { return }
                let key = url.absoluteString.lowercased()
                guard !seen.contains(key) else { return }
                seen.insert(key)
                urls.append(url)
            }
        }

        return urls
    }

    func detectedHTTPImageURLs() -> [URL] {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tif", "tiff"]

        return detectedURLs().filter { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return false
            }
            return imageExtensions.contains(url.pathExtension.lowercased())
        }
    }
}
