import Foundation
import Testing
@testable import NowDockCore

@Test func estimateCountsTrashSeparatorsAndSafety() {
    let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let prefs = DockPrefs(tileSize: 49, largeSize: 128, magnification: true, persistentCount: 25)
    let frame = estimateDockFrame(screenFrame: screen, prefs: prefs)
    let naive = CGFloat(25) * (49 + 4)
    #expect(frame.width > naive)
    let expected: CGFloat = 26 * 53 + 40 + 12 + (128 - 49)
    #expect(frame.width == expected)
    #expect(frame.height == 65)
}

@Test func estimateMagnificationAddsHeadroom() {
    let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let off = estimateDockFrame(
        screenFrame: screen,
        prefs: DockPrefs(tileSize: 48, largeSize: 128, magnification: false, persistentCount: 10)
    )
    let on = estimateDockFrame(
        screenFrame: screen,
        prefs: DockPrefs(tileSize: 48, largeSize: 128, magnification: true, persistentCount: 10)
    )
    #expect(on.width == off.width + (128 - 48))
}

@Test func estimateReservesTrashWhenOthersCountIsZero() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = estimateDockFrame(screenFrame: screen, prefs: DockPrefs(othersCount: 0))
    #expect(frame.width == CGFloat(1 * 52 + 40 + 12))
}

@Test func estimateCapsWidthOnNarrowScreens() {
    let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
    let prefs = DockPrefs(tileSize: 48, persistentCount: 50)
    let frame = estimateDockFrame(screenFrame: screen, prefs: prefs)
    #expect(frame.width == 352)
}

@Test func estimateRespectsBottomMargin() {
    let screen = CGRect(x: 100, y: 80, width: 1440, height: 900)
    let frame = estimateDockFrame(screenFrame: screen, prefs: DockPrefs(), bottomMargin: 12)
    #expect(frame.minY == 92)
    #expect(frame.midX == screen.midX)
}
