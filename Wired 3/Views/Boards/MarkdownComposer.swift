import SwiftUI
import AppKit

struct MarkdownComposer: View {
    @Binding var text: String
    var minHeight: CGFloat = 180

    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                button("B", help: "Gras") { wrapSelection(prefix: "**", suffix: "**", placeholder: "bold") }
                button("I", help: "Italique") { wrapSelection(prefix: "*", suffix: "*", placeholder: "italic") }
                button("Code", help: "Code inline") { wrapSelection(prefix: "`", suffix: "`", placeholder: "code") }
                button("Link", help: "Lien") { insertLink() }
                button("Img", help: "Image") { insertImage() }
                button("Quote", help: "Citation") { prefixLines(with: "> ") }
                button("List", help: "Liste") { prefixLines(with: "- ") }
                Spacer(minLength: 0)
            }

            MarkdownTextView(text: $text, selectedRange: $selectedRange)
                .frame(minHeight: minHeight)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private func button(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(help)
    }

    private func clampedRange(in value: String) -> NSRange {
        let maxLength = (value as NSString).length
        let location = min(max(0, selectedRange.location), maxLength)
        let length = min(max(0, selectedRange.length), maxLength - location)
        return NSRange(location: location, length: length)
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let selected = range.length > 0 ? ns.substring(with: range) : placeholder
        let replacement = prefix + selected + suffix
        text = ns.replacingCharacters(in: range, with: replacement)

        if range.length > 0 {
            let caret = range.location + (replacement as NSString).length
            selectedRange = NSRange(location: caret, length: 0)
        } else {
            selectedRange = NSRange(location: range.location + (prefix as NSString).length, length: (selected as NSString).length)
        }
    }

    private func insertLink() {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let selected = range.length > 0 ? ns.substring(with: range) : "label"
        let replacement = "[\(selected)](https://)"
        text = ns.replacingCharacters(in: range, with: replacement)

        let linkStart = range.location + ("[\(selected)](" as NSString).length
        selectedRange = NSRange(location: linkStart, length: ("https://" as NSString).length)
    }

    private func insertImage() {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let replacement = "![alt](https://)"
        text = ns.replacingCharacters(in: range, with: replacement)

        let altStart = range.location + ("![" as NSString).length
        selectedRange = NSRange(location: altStart, length: ("alt" as NSString).length)
    }

    private func prefixLines(with prefix: String) {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let lineRange = ns.lineRange(for: range)
        let chunk = ns.substring(with: lineRange)
        let lines = chunk.components(separatedBy: "\n")
        let transformed = lines.map { line -> String in
            if line.isEmpty { return prefix }
            if line.hasPrefix(prefix) { return line }
            return prefix + line
        }.joined(separator: "\n")

        text = ns.replacingCharacters(in: lineRange, with: transformed)
        selectedRange = NSRange(location: lineRange.location, length: (transformed as NSString).length)
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            context.coordinator.isProgrammaticChange = false
        }

        let maxLength = (textView.string as NSString).length
        let location = min(max(0, selectedRange.location), maxLength)
        let length = min(max(0, selectedRange.length), maxLength - location)
        let clamped = NSRange(location: location, length: length)

        if !NSEqualRanges(textView.selectedRange(), clamped) {
            context.coordinator.isProgrammaticChange = true
            textView.setSelectedRange(clamped)
            context.coordinator.isProgrammaticChange = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        weak var textView: NSTextView?
        var isProgrammaticChange = false

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let textView else { return }
            text = textView.string
            selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticChange, let textView else { return }
            selectedRange = textView.selectedRange()
        }
    }
}
