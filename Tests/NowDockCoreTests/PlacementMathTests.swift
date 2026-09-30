import Foundation
import Testing
@testable import NowDockCore

@Test func placementFullHugsDock() {
    expectVisible(
        makeInput(dockMinX: 800),
        frame: CGRect(x: 388, y: 4, width: 400, height: 70),
        layout: .full
    )
}

@Test func placementFullOnSecondaryScreen() {
    let input = PlacementInput(
        screenFrame: CGRect(x: 1920, y: 0, width: 1440, height: 900),
        dockFrame: CGRect(x: 2820, y: 6, width: 500, height: 64),
        dockGap: 12
    )
    expectVisible(input, frame: CGRect(x: 2408, y: 6, width: 400, height: 64), layout: .full)
}

@Test func placementExactFullSpan() {
    expectVisible(
        makeInput(dockMinX: 418),
        frame: CGRect(x: 6, y: 4, width: 400, height: 70),
        layout: .full
    )
}

@Test func placementOnePointUnderFull() {
    expectVisible(
        makeInput(dockMinX: 417),
        frame: CGRect(x: 125, y: 4, width: 280, height: 70),
        layout: .compact
    )
}

@Test func placementExactCompactSpan() {
    expectVisible(
        makeInput(dockMinX: 298),
        frame: CGRect(x: 6, y: 4, width: 280, height: 70),
        layout: .compact
    )
}

@Test func placementOnePointUnderCompact() {
    expectVisible(
        makeInput(dockMinX: 297),
        frame: CGRect(x: 85, y: 4, width: 200, height: 70),
        layout: .minimal
    )
}

@Test func placementExactMinimalSpan() {
    expectVisible(
        makeInput(dockMinX: 218),
        frame: CGRect(x: 6, y: 4, width: 200, height: 70),
        layout: .minimal
    )
}

@Test func placementHiddenBelowMinimal() {
    #expect(placement(for: makeInput(dockMinX: 217)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 124)) == .hidden)
}

@Test func placementHiddenWhenHeightIsZero() {
    #expect(placement(for: makeInput(dockMinX: 800, dockHeight: 0)) == .hidden)
}

@Test func placementHiddenWhenDockIsNotInsideScreen() {
    #expect(placement(for: makeInput(dockMinX: 0)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 1440)) == .hidden)
}

@Test func placementLargePresetShiftsLeftKeepsRung() {
    expectVisible(
        makeInput(dockMinX: 800, dockGap: 28),
        frame: CGRect(x: 372, y: 4, width: 400, height: 70),
        layout: .full
    )
}

@Test func placementGapBelowFloorClampsToMinimum() {
    expectVisible(
        makeInput(dockMinX: 800, dockGap: 0),
        frame: CGRect(x: 388, y: 4, width: 400, height: 70),
        layout: .full
    )
}

@Test func placementHiddenWhenGapIsNonFinite() {
    #expect(placement(for: makeInput(dockMinX: 800, dockGap: .nan)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 800, dockGap: .infinity)) == .hidden)
}

@Test func placementSweepHoldsHugAndRungInvariants() {
    for gap: CGFloat in [12, 18, 28] {
        for dockMinX: CGFloat in stride(from: 200.0, through: 1200.0, by: 7) {
            let input = makeInput(dockMinX: dockMinX, dockGap: gap)
            let span = dockMinX - gap - 6
            switch placement(for: input) {
            case .visible(let placed):
                #expect(span >= 200)
                #expect(placed.frame.maxX == dockMinX - gap)
                #expect(placed.frame.width == placed.layout.rungWidth)
            case .hidden:
                #expect(span < 200)
            }
        }
    }
}

private func makeInput(dockMinX: CGFloat, dockHeight: CGFloat = 70, dockGap: CGFloat = 12) -> PlacementInput {
    PlacementInput(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        dockFrame: CGRect(x: dockMinX, y: 4, width: 400, height: dockHeight),
        dockGap: dockGap
    )
}

private func expectVisible(_ input: PlacementInput, frame: CGRect, layout: PanelLayout) {
    guard case .visible(let placed) = placement(for: input) else {
        Issue.record("expected visible, got hidden")
        return
    }
    #expect(placed.frame == frame)
    #expect(placed.layout == layout)
    let appliedGap = max(EdgeGapPreset.minimum, input.dockGap)
    #expect(placed.frame.maxX == input.dockFrame.minX - appliedGap)
    #expect(placed.frame.width == placed.layout.rungWidth)
}
