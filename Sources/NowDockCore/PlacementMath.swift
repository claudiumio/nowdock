import CoreGraphics
import Foundation

private enum WidthLadder {
    /// Left floor. Keeps the pill on the screen. Independent of the Dock clearance.
    static let screenFloor: CGFloat = 6

    static let descending: [PanelLayout] =
        PanelLayout.allCases.sorted { $0.rungWidth > $1.rungWidth }

    static func widest(fitting available: CGFloat) -> PanelLayout? {
        descending.first { $0.rungWidth <= available }
    }
}

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
    let leftLimit = screen.minX + WidthLadder.screenFloor
    guard let layout = WidthLadder.widest(fitting: right - leftLimit) else {
        return .hidden
    }
    let width = layout.rungWidth
    let frame = CGRect(x: right - width, y: dock.minY, width: width, height: dock.height)
    return .visible(PlacedPanel(frame: frame, layout: layout))
}
