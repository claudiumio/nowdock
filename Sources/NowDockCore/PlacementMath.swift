import CoreGraphics
import Foundation

public func placement(for input: PlacementInput) -> PlacementResult {
    let screen = input.screenFrame
    let dock = input.dockFrame
    guard dock.height > 0, dock.minX > screen.minX, dock.minX < screen.maxX else {
        return .hidden
    }

    let x = screen.minX + input.edgeGap
    let width = min(input.maxWidth, dock.minX - input.edgeGap - x)
    guard width >= input.minWidth else {
        return .hidden
    }

    let layout: PanelLayout
    if width >= 420 {
        layout = .full
    } else if width >= 300 {
        layout = .compact
    } else {
        layout = .minimal
    }

    return .visible(
        frame: CGRect(x: x, y: dock.minY, width: width, height: dock.height),
        layout: layout
    )
}
