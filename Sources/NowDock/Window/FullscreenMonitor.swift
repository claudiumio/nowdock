import AppKit
import CoreGraphics

final class FullscreenMonitor {
    var screenFrame: () -> CGRect = { .zero }
    var isFullscreen: ((Bool) -> Void)?

    private var lastValue: Bool?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }
        workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }
        evaluate()
    }

    func evaluate() {
        let screen = screenFrame()
        guard screen.width > 0, screen.height > 0 else {
            publish(false)
            return
        }
        let quartzScreen = DockGeometry.quartzRect(fromAppKit: screen)
        let ours = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            publish(false)
            return
        }

        let found = info.contains { window in
            guard intValue(window[kCGWindowLayer as String]) == 0 else { return false }
            guard pidValue(window[kCGWindowOwnerPID as String]) != ours else { return false }
            var bounds = CGRect.zero
            guard let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  CGRectMakeWithDictionaryRepresentation(dict, &bounds)
            else { return false }
            return bounds.approximatelyMatches(quartzScreen)
        }
        publish(found)
    }

    private func publish(_ value: Bool) {
        guard lastValue != value else { return }
        lastValue = value
        isFullscreen?(value)
    }
}

private func intValue(_ any: Any?) -> Int? {
    if let value = any as? Int { return value }
    if let number = any as? NSNumber { return number.intValue }
    return nil
}

private func pidValue(_ any: Any?) -> pid_t {
    if let value = any as? pid_t { return value }
    if let value = any as? Int { return pid_t(value) }
    if let number = any as? NSNumber { return number.int32Value }
    return 0
}

private extension CGRect {
    func approximatelyMatches(_ other: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
