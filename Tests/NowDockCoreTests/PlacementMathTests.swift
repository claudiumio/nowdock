import Foundation
import Testing
@testable import NowDockCore

@Test func placementFullHugsDock() {
    expectVisible(
        makeInput(dockMinX: 800),
        frame: CGRect(x: 228, y: 4, width: 560, height: 70),
        layout: .full
    )
}

@Test func placementFullOnSecondaryScreen() {
    let input = PlacementInput(
        screenFrame: CGRect(x: 1920, y: 0, width: 1440, height: 900),
        dockFrame: CGRect(x: 2820, y: 6, width: 500, height: 64),
        dockGap: 12
    )
    expectVisible(input, frame: CGRect(x: 2248, y: 6, width: 560, height: 64), layout: .full)
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
        frame: CGRect(x: 6, y: 4, width: 399, height: 70),
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
        frame: CGRect(x: 6, y: 4, width: 279, height: 70),
        layout: .minimal
    )
}

@Test func placementTightMinimalKeepsInvariantWidth() {
    expectVisible(
        makeInput(dockMinX: 170),
        frame: CGRect(x: 6, y: 4, width: 152, height: 70),
        layout: .minimal
    )
}

@Test func placementExactMinimalFloor() {
    expectVisible(
        makeInput(dockMinX: 114),
        frame: CGRect(x: 6, y: 4, width: 96, height: 70),
        layout: .minimal
    )
}

@Test func placementHiddenBelowMinimalFloor() {
    #expect(placement(for: makeInput(dockMinX: 113)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 60)) == .hidden)
}

@Test func placementFitsCurrentDockWithoutReducingClearance() {
    let input = PlacementInput(
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        dockFrame: CGRect(x: 131.5, y: 6, width: 1657, height: 65),
        dockGap: 12
    )
    expectVisible(input, frame: CGRect(x: 6, y: 6, width: 113.5, height: 65), layout: .minimal)
}

@Test func placementHiddenWhenHeightIsZero() {
    #expect(placement(for: makeInput(dockMinX: 800, dockHeight: 0)) == .hidden)
}

@Test func placementHiddenWhenDockIsNotInsideScreen() {
    #expect(placement(for: makeInput(dockMinX: 0)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 1440)) == .hidden)
}

@Test func placementLargePresetShiftsLeftKeepsWidth() {
    expectVisible(
        makeInput(dockMinX: 800, dockGap: 28),
        frame: CGRect(x: 212, y: 4, width: 560, height: 70),
        layout: .full
    )
}

@Test func placementGapBelowFloorClampsToMinimum() {
    expectVisible(
        makeInput(dockMinX: 800, dockGap: 0),
        frame: CGRect(x: 228, y: 4, width: 560, height: 70),
        layout: .full
    )
}

@Test func placementHiddenWhenGapIsNonFinite() {
    #expect(placement(for: makeInput(dockMinX: 800, dockGap: .nan)) == .hidden)
    #expect(placement(for: makeInput(dockMinX: 800, dockGap: .infinity)) == .hidden)
}

@Test func placementSweepHoldsHugAndThresholdInvariants() {
    for gap: CGFloat in [12, 18, 28] {
        for dockMinX: CGFloat in stride(from: 100.0, through: 1200.0, by: 7) {
            let input = makeInput(dockMinX: dockMinX, dockGap: gap)
            let span = dockMinX - gap - 6
            let width = min(PanelLayout.maxWidth, span)
            switch placement(for: input) {
            case .visible(let placed):
                #expect(placed.frame.width == width)
                #expect(placed.frame.maxX == dockMinX - gap)
                #expect(placed.layout == PanelLayout.layout(forWidth: width))
            case .hidden:
                #expect(PanelLayout.layout(forWidth: width) == nil)
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
    #expect(placed.frame.width <= PanelLayout.maxWidth)
}
