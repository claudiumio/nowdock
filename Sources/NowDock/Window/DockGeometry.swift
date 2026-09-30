import AppKit
import NowDockCore

enum DockGeometry {
    enum Orientation {
        case bottom, left, right
    }

    struct Snapshot {
        var frame: CGRect
        var screenFrame: CGRect
        var orientation: Orientation
        var autohide: Bool
    }

    static var orientation: Orientation {
        switch dockDefaults.string(forKey: "orientation") {
        case "left": .left
        case "right": .right
        default: .bottom
        }
    }

    static var autohide: Bool {
        dockDefaults.bool(forKey: "autohide")
    }

    static func snapshot(bottomMargin: CGFloat = 6) -> Snapshot {
        let screen = fallbackDockScreen()
        let screenFrame = screen?.frame ?? .zero
        let prefs = currentPrefs()
        var frame = estimateDockFrame(screenFrame: screenFrame, prefs: prefs, bottomMargin: bottomMargin)
        // Escape hatch for fine-tuning without a rebuild:
        // defaults write dev.nowdock.NowDock dockWidthAdjust -float 20
        let adjust = UserDefaults.standard.object(forKey: "dockWidthAdjust") as? NSNumber
        if let adjust, adjust.doubleValue != 0 {
            frame.size.width += CGFloat(adjust.doubleValue)
            frame.origin.x -= CGFloat(adjust.doubleValue) / 2
        }
        return Snapshot(
            frame: frame,
            screenFrame: screenFrame,
            orientation: orientation,
            autohide: autohide
        )
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func quartzRect(fromAppKit appKit: CGRect) -> CGRect {
        CGRect(
            x: appKit.origin.x,
            y: primaryMaxY - appKit.origin.y - appKit.height,
            width: appKit.width,
            height: appKit.height
        )
    }

    private static var primaryMaxY: CGFloat {
        let screens = NSScreen.screens
        if let primary = screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.maxY
        }
        return screens.first?.frame.maxY ?? 0
    }

    private static var dockDefaults: UserDefaults {
        UserDefaults(suiteName: "com.apple.dock") ?? .standard
    }

    private static func currentPrefs() -> DockPrefs {
        let defaults = dockDefaults
        let rawTile = defaults.integer(forKey: "tilesize")
        let rawLarge = defaults.integer(forKey: "largesize")
        let persistentCount = (defaults.array(forKey: "persistent-apps") as? [Any])?.count ?? 0
        let othersCount = (defaults.array(forKey: "persistent-others") as? [Any])?.count ?? 0
        let showRecents = (defaults.object(forKey: "show-recents") as? Bool) ?? true
        let recentsCount = showRecents
            ? ((defaults.array(forKey: "recent-apps") as? [Any])?.count ?? 0)
            : 0
        let pinned = (defaults.array(forKey: "persistent-apps") as? [[String: Any]]) ?? []
        let pinnedBundles = Set(pinned.compactMap {
            ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        })
        // Exact diff: a count subtraction misses unpinned running apps when
        // fewer apps run than are pinned (3 invisible tiles ≈ 160 px of overlap).
        let runningExtras = NSWorkspace.shared.runningApplications.filter {
            guard $0.activationPolicy == .regular else { return false }
            guard let bid = $0.bundleIdentifier else { return true }
            return !pinnedBundles.contains(bid)
        }.count
        return DockPrefs(
            tileSize: CGFloat(rawTile > 0 ? rawTile : 48),
            largeSize: CGFloat(rawLarge > 0 ? rawLarge : 128),
            magnification: defaults.bool(forKey: "magnification"),
            persistentCount: pinned.count,
            othersCount: othersCount,
            recentsCount: recentsCount,
            runningExtraCount: runningExtras
        )
    }

    private static func fallbackDockScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let best = screens.max(by: {
            ($0.visibleFrame.minY - $0.frame.minY) < ($1.visibleFrame.minY - $1.frame.minY)
        }), best.visibleFrame.minY - best.frame.minY > 1 {
            return best
        }
        return NSScreen.main ?? screens.first
    }
}
