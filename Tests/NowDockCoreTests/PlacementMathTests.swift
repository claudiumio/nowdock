import Foundation
import Testing
@testable import NowDockCore

@Test func placementFullLayout() {
    let result = placement(for: makeInput(dockMinX: 800))
    #expect(result == .visible(
        frame: CGRect(x: 12, y: 4, width: 560, height: 70),
        layout: .full
    ))
}

@Test func placementCompactLayout() {
    let result = placement(for: makeInput(dockMinX: 374))
    #expect(result == .visible(
        frame: CGRect(x: 12, y: 4, width: 350, height: 70),
        layout: .compact
    ))
}

@Test func placementMinimalLayout() {
    let result = placement(for: makeInput(dockMinX: 274))
    #expect(result == .visible(
        frame: CGRect(x: 12, y: 4, width: 250, height: 70),
        layout: .minimal
    ))
}

@Test func placementHiddenWhenGapIsNarrow() {
    #expect(placement(for: makeInput(dockMinX: 124)) == .hidden)
}

@Test func placementHiddenWhenHeightIsZero() {
    #expect(placement(for: makeInput(dockMinX: 800, dockHeight: 0)) == .hidden)
}

@Test func placementHiddenWhenDockIsNotLeftOfScreenEdge() {
    #expect(placement(for: makeInput(dockMinX: 0)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 1440)) == .hidden)
}

@Test func placementLayoutBoundaries() {
    #expect(layout(forWidth: 420) == .full)
    #expect(layout(forWidth: 419) == .compact)
    #expect(layout(forWidth: 300) == .compact)
    #expect(layout(forWidth: 299) == .minimal)
    #expect(layout(forWidth: 220) == .minimal)
    #expect(layout(forWidth: 200) == .minimal)
    #expect(placement(for: makeInput(dockMinX: 223)) == .hidden)
}

private func makeInput(dockMinX: CGFloat, dockHeight: CGFloat = 70) -> PlacementInput {
    PlacementInput(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        dockFrame: CGRect(x: dockMinX, y: 4, width: 400, height: dockHeight),
        edgeGap: 12
    )
}

private func layout(forWidth width: CGFloat) -> PanelLayout? {
    if case .visible(_, let layout) = placement(for: makeInput(dockMinX: width + 24)) {
        return layout
    }
    return nil
}
