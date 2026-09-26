import AppKit
import SwiftUI

final class FirstMouseHostingView: NSHostingView<CompanionView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class GlassContainerView: NSView {
    private let effectView: NSView

    override init(frame frameRect: NSRect) {
        if #available(macOS 26, *) {
            effectView = NSGlassEffectView(frame: .zero)
        } else {
            let visual = NSVisualEffectView(frame: .zero)
            visual.material = .hudWindow
            visual.state = .active
            visual.blendingMode = .behindWindow
            effectView = visual
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        autoresizingMask = [.width, .height]
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)
        applyCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func embed(_ content: NSView) {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26, *), let glass = effectView as? NSGlassEffectView {
            glass.contentView = content
        } else {
            content.frame = effectView.bounds
            effectView.addSubview(content)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyCornerRadius()
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        let glassManaged: Bool
        if #available(macOS 26, *) {
            glassManaged = effectView is NSGlassEffectView
        } else {
            glassManaged = false
        }
        if !glassManaged {
            effectView.subviews.first?.frame = effectView.bounds
        }
        applyCornerRadius()
    }

    private func applyCornerRadius() {
        let radius = bounds.height * 0.3
        layer?.cornerRadius = radius
        if #available(macOS 26, *), let glass = effectView as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = radius
            effectView.layer?.masksToBounds = true
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var center: NowPlayingCenter?
    private var windowController: CompanionWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NowPlayingCenter()
        let controller = CompanionWindowController()
        self.center = center
        self.windowController = controller

        let hosting = FirstMouseHostingView(rootView: CompanionView(center: center, window: controller))
        hosting.sizingOptions = []

        let container = GlassContainerView(frame: .zero)
        container.embed(hosting)
        controller.setContentView(container)
        controller.onVisibilityChange = { [center] visible in
            center.isProgressActive = visible
        }
        center.start()
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
