import Foundation
import Testing
@testable import NowDockCore

@Test func elapsedWhilePlayingAddsDelta() {
    let stamp = Date(timeIntervalSince1970: 1_000)
    let state = NowPlayingState(
        track: TrackInfo(id: "1", title: "T", artist: "A", duration: 200),
        status: .playing,
        position: 10,
        positionTimestamp: stamp
    )
    #expect(state.elapsed(at: stamp.addingTimeInterval(5)) == 15)
}

@Test func elapsedWhilePausedStaysAtPosition() {
    let stamp = Date(timeIntervalSince1970: 1_000)
    let state = NowPlayingState(
        track: TrackInfo(id: "1", title: "T", artist: "A", duration: 200),
        status: .paused,
        position: 10,
        positionTimestamp: stamp
    )
    #expect(state.elapsed(at: stamp.addingTimeInterval(5)) == 10)
}

@Test func elapsedClampsToDuration() {
    let stamp = Date(timeIntervalSince1970: 1_000)
    let state = NowPlayingState(
        track: TrackInfo(id: "1", title: "T", artist: "A", duration: 12),
        status: .playing,
        position: 10,
        positionTimestamp: stamp
    )
    #expect(state.elapsed(at: stamp.addingTimeInterval(10)) == 12)
}
