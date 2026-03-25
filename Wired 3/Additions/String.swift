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
        underlineLinks: Bool = true,
        highlightQuery: String? = nil,
        highlightColor: Color = .yellow.opacity(0.35)
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

        attributed.applyHighlights(
            query: highlightQuery,
            highlightColor: highlightColor
        )

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

private extension AttributedString {
    mutating func applyHighlights(query: String?, highlightColor: Color) {
        let tokens = Self.searchHighlightTokens(from: query)
        guard !tokens.isEmpty else { return }

        let renderedString = String(characters)
        for token in tokens {
            var searchStart = renderedString.startIndex

            while searchStart < renderedString.endIndex,
                  let range = renderedString.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<renderedString.endIndex
                  ) {
                guard let lower = AttributedString.Index(range.lowerBound, within: self),
                      let upper = AttributedString.Index(range.upperBound, within: self) else {
                    searchStart = range.upperBound
                    continue
                }

                self[lower..<upper].backgroundColor = highlightColor
                searchStart = range.upperBound
            }
        }
    }

    private static func searchHighlightTokens(from query: String?) -> [String] {
        guard let query else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen: Set<String> = []
        let candidates = ([trimmed] + trimmed.split(whereSeparator: \.isWhitespace).map(String.init))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }

        let unique = candidates.filter { token in
            let key = token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted
        }

        return unique.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs < rhs
        }
    }
}
