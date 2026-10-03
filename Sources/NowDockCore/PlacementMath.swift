import CoreGraphics
import Foundation

/// Left floor. Keeps the pill on the screen. Independent of the Dock clearance.
private let screenFloor: CGFloat = 6

public func placement(for input: PlacementInput) -> PlacementResult {
    let screen = input.screenFrame
    let dock = input.dockFrame
    guard dock.height > 0, dock.minX > screen.minX, dock.minX < screen.maxX else {
        return .hidden
    }
    guard input.dockGap.isFinite, screen.width.isFinite else {
        return .hidden
    }
    let gap = max(EdgeGapPreset.minimum, input.dockGap)
    let right = dock.minX - gap
    let width = min(PanelLayout.maxWidth, right - (screen.minX + screenFloor))
    guard let layout = PanelLayout.layout(forWidth: width) else {
        return .hidden
    }
    let frame = CGRect(x: right - width, y: dock.minY, width: width, height: dock.height)
    return .visible(PlacedPanel(frame: frame, layout: layout))
}
