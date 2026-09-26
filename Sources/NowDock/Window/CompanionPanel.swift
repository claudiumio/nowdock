import AppKit

final class CompanionPanel: NSPanel {
    private let host = FirstMouseHost()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = host
        applyCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        applyCornerRadius()
    }

    func setContent(_ view: NSView) {
        host.install(view)
    }

    private func applyCornerRadius() {
        host.wantsLayer = true
        host.layer?.cornerRadius = frame.height * 0.3
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
    }
}

private final class FirstMouseHost: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func install(_ view: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        addSubview(view)
    }
}
