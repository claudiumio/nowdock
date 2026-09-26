import AppKit
import Combine
import NowDockCore
import os
@MainActor
final class CompanionWindowController: ObservableObject {
    @Published private(set) var layout: PanelLayout = .full
    @Published private(set) var isUnavailable = false
    @Published private(set) var isPanelVisible = false

    var onVisibilityChange: ((Bool) -> Void)?

    var edgeGapPreset: EdgeGapPreset {
        get { storedGap }
        set {
            guard newValue != storedGap else { return }
            storedGap = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.edgeGapKey)
            if started { scheduleRelayout() }
        }
    }

    private static let edgeGapKey = "edgeGapPreset"

    private let panel = CompanionPanel()
    private let fullscreen = FullscreenMonitor()
    private let hover = HoverRevealController()

    private var storedGap: EdgeGapPreset
    private var started = false
    private var hasPlacement = false
    private var fullscreenActive = false
    private var dockScreenFrame = NSRect.zero
    private var debounce: DispatchWorkItem?
    private var fadeGeneration = 0

    init() {
        storedGap = EdgeGapPreset(rawValue: UserDefaults.standard.string(forKey: Self.edgeGapKey) ?? "")
            ?? .matchDock
        fullscreen.screenFrame = { [weak self] in
            self?.dockScreenFrame ?? .zero
        }
        fullscreen.isFullscreen = { [weak self] flag in
            guard let self else { return }
            self.fullscreenActive = flag
            self.applyRevealMode()
        }
        hover.targetRect = { [weak self] in
            self?.panel.frame ?? .zero
        }
        hover.onShow = { [weak self] in self?.fade(true) }
        hover.onHide = { [weak self] in self?.fade(false) }
    }

    func setContentView(_ view: NSView) {
        panel.setContent(view)
    }

    func start() {
        guard !started else { return }
        started = true
        installObservers()
        fullscreen.start()
        relayout()
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSApplication.didChangeScreenParametersNotification, on: .default)
        observe(NSWorkspace.didLaunchApplicationNotification, on: workspace)
        observe(NSWorkspace.didTerminateApplicationNotification, on: workspace)
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspace)
        _ = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRelayout()
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRelayout()
        }
    }

    private func scheduleRelayout() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.relayout() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func relayout() {
        let margin = UserDefaults.standard.object(forKey: "dockBottomMargin") as? NSNumber
        let snap = DockGeometry.snapshot(bottomMargin: margin.map { CGFloat(truncating: $0) } ?? 6)
        isUnavailable = snap.orientation != .bottom
        dockScreenFrame = snap.screenFrame

        guard !isUnavailable else {
            hasPlacement = false
            hover.isRevealArmed = false
            fade(false)
            return
        }

        let screen = DockGeometry.screen(containing: snap.frame)
        if let screen {
            dockScreenFrame = screen.frame
        }
        let screenFrame = screen?.frame ?? snap.screenFrame
        let inset = max(0, snap.frame.minY - screenFrame.minY)
        let input = PlacementInput(
            screenFrame: screenFrame,
            dockFrame: snap.frame,
            edgeGap: storedGap.value(dockBottomInset: inset)
        )

        switch placement(for: input) {
        case .visible(let frame, let newLayout):
            layout = newLayout
            panel.setFrame(frame, display: true)
            hasPlacement = true
            Logger.nowDockWindow.info("dock=\(self.rect(snap.frame), privacy: .public) panel=\(self.rect(frame), privacy: .public) layout=\(String(describing: newLayout), privacy: .public)")
            applyRevealMode()
        case .hidden:
            hasPlacement = false
            hover.isRevealArmed = false
            Logger.nowDockWindow.info("dock=\(self.rect(snap.frame), privacy: .public) panel=hidden")
            fade(false)
        }
    }

    private func applyRevealMode() {
        guard hasPlacement, !isUnavailable else {
            hover.isRevealArmed = false
            fade(false)
            return
        }
        let armed = fullscreenActive || DockGeometry.autohide
        hover.isRevealArmed = armed
        if armed {
            if !hover.isRevealed { fade(false) }
        } else {
            fade(true)
        }
    }

    private func fade(_ show: Bool) {
        guard show != isPanelVisible else { return }
        fadeGeneration += 1
        let generation = fadeGeneration

        if show {
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
            publishVisible(true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, generation == self.fadeGeneration else { return }
                self.panel.orderOut(nil)
            }
            publishVisible(false)
        }
    }

    private func publishVisible(_ visible: Bool) {
        guard visible != isPanelVisible else { return }
        isPanelVisible = visible
        onVisibilityChange?(visible)
    }

    private func rect(_ rect: CGRect) -> String {
        String(format: "(%.0f, %.0f, %.0f, %.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }
}
