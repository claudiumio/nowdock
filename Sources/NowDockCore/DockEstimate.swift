import CoreGraphics
import Foundation

public struct DockPrefs: Sendable, Equatable {
    public var tileSize: CGFloat
    public var largeSize: CGFloat
    public var magnification: Bool
    public var persistentCount: Int
    public var othersCount: Int
    public var recentsCount: Int
    public var runningExtraCount: Int

    public init(
        tileSize: CGFloat = 48,
        largeSize: CGFloat = 128,
        magnification: Bool = false,
        persistentCount: Int = 0,
        othersCount: Int = 0,
        recentsCount: Int = 0,
        runningExtraCount: Int = 0
    ) {
        self.tileSize = tileSize
        self.largeSize = largeSize
        self.magnification = magnification
        self.persistentCount = persistentCount
        self.othersCount = othersCount
        self.recentsCount = recentsCount
        self.runningExtraCount = runningExtraCount
    }
}

public func estimateDockFrame(
    screenFrame: CGRect,
    prefs: DockPrefs,
    bottomMargin: CGFloat = 6
) -> CGRect {
    // Tuned against a real 1920px Dock (25 tiles @49, magnification on): pitch
    // +4, separators/padding +40, safety +12, one tile of magnification growth.
    // Conservative enough to avoid overlap, lean enough to leave room.
    let pitch = prefs.tileSize + 4
    let tiles = prefs.persistentCount
        + prefs.othersCount
        + prefs.recentsCount
        + prefs.runningExtraCount
        + 1 // Trash, always present
    var width = CGFloat(tiles) * pitch + 40 + 12
    if prefs.magnification {
        width += prefs.largeSize - prefs.tileSize
    }
    width = min(width, screenFrame.width - 48)
    let height = prefs.tileSize + 16
    return CGRect(
        x: screenFrame.midX - width / 2,
        y: screenFrame.minY + bottomMargin,
        width: width,
        height: height
    )
}
