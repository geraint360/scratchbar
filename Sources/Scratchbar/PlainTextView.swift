import AppKit

/// Plain-text editor: pastes never carry formatting, and the "smart" text
/// substitutions are off so code and commands paste exactly as copied.
final class PlainTextView: NSTextView {
    static let defaultFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 9...36

    static func makeScrollable() -> (NSScrollView, PlainTextView) {
        let scroll = NSTextView.scrollableTextView()
        let textView = PlainTextView(frame: scroll.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        textView.configure()
        return (scroll, textView)
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        drawsBackground = false
        textColor = Theme.text
        insertionPointColor = Theme.text
        selectedTextAttributes = [.backgroundColor: Theme.selection]
        textContainerInset = NSSize(width: 6, height: 8)
        applyFontSize(UserDefaults.standard.object(forKey: DefaultsKey.fontSize) as? CGFloat ?? Self.defaultFontSize)
    }

    func applyFontSize(_ size: CGFloat) {
        let clamped = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        let font = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
        self.font = font
        typingAttributes[.font] = font
        typingAttributes[.foregroundColor] = Theme.text
        UserDefaults.standard.set(clamped, forKey: DefaultsKey.fontSize)
    }

    var fontSize: CGFloat { font?.pointSize ?? Self.defaultFontSize }

    /// Shades `ranges` (search matches) without changing the text itself, so
    /// nothing is saved, undone or copied with it.
    func highlight(_ ranges: [NSRange]) {
        let length = (string as NSString).length
        if let layout = textLayoutManager, let content = layout.textContentManager {
            layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
            for range in ranges where NSMaxRange(range) <= length {
                guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                      let end = content.location(start, offsetBy: range.length),
                      let textRange = NSTextRange(location: start, end: end) else { continue }
                layout.addRenderingAttribute(.backgroundColor, value: Theme.match, for: textRange)
            }
        } else if let layout = layoutManager {
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for range in ranges where NSMaxRange(range) <= length {
                layout.addTemporaryAttribute(.backgroundColor, value: Theme.match, forCharacterRange: range)
            }
        }
    }

    // Esc is bound to `complete:` in text views; make it close the window instead.
    override func complete(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }
}
