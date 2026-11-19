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

    // Esc is bound to `complete:` in text views; make it close the window instead.
    override func complete(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }
}
