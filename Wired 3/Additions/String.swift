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
}
