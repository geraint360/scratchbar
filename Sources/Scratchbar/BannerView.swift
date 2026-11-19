import AppKit

/// A strip above the editor with a message and a few buttons.
final class BannerView: NSView {
    init(message: String, buttons: [(String, () -> Void)]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.lineBreakMode = .byTruncatingTail

        var views: [NSView] = [icon, label]
        for (title, handler) in buttons {
            let button = ActionButton(title: title, handler: handler)
            button.controlSize = .small
            button.bezelStyle = .push
            views.append(button)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.setCustomSpacing(10, after: label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// An NSButton that runs a closure.
private final class ActionButton: NSButton {
    private var handler: () -> Void = {}

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(run)
    }

    @objc private func run() { handler() }
}
