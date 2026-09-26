import AppKit

@MainActor
final class HoverRevealController {
    var targetRect: () -> CGRect = { .zero }
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    private(set) var isRevealed = false

    var isRevealArmed = false {
        didSet {
            guard isRevealArmed != oldValue else { return }
            syncMonitor()
        }
    }

    private var monitor: Any?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    private func syncMonitor() {
        cancelWork()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard isRevealArmed else {
            isRevealed = false
            return
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            let point = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.consider(point)
            }
        }
        consider(NSEvent.mouseLocation)
    }

    private func consider(_ point: CGPoint) {
        guard isRevealArmed else { return }
        if targetRect().contains(point) {
            hideWork?.cancel()
            hideWork = nil
            guard !isRevealed, showWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isRevealArmed else { return }
                self.showWork = nil
                self.isRevealed = true
                self.onShow?()
            }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            showWork?.cancel()
            showWork = nil
            guard isRevealed, hideWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isRevealArmed else { return }
                self.hideWork = nil
                self.isRevealed = false
                self.onHide?()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
    }

    private func cancelWork() {
        showWork?.cancel()
        hideWork?.cancel()
        showWork = nil
        hideWork = nil
    }
}
