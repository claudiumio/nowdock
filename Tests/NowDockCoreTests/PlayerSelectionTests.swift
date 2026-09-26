import Foundation
import Testing
@testable import NowDockCore

@Test func selectActivePlayerKeepsCurrentCandidate() {
    let older = Date(timeIntervalSince1970: 10)
    let newer = Date(timeIntervalSince1970: 20)
    let selected = selectActivePlayer(
        current: .spotify,
        activities: [
            activity(.spotify, status: .paused, becamePlayingAt: older),
            activity(.appleMusic, status: .playing, becamePlayingAt: newer),
        ]
    )
    #expect(selected == .spotify)
}

@Test func selectActivePlayerPrefersMostRecentPlaying() {
    let older = Date(timeIntervalSince1970: 10)
    let newer = Date(timeIntervalSince1970: 20)
    let selected = selectActivePlayer(
        current: nil,
        activities: [
            activity(.spotify, status: .playing, becamePlayingAt: older),
            activity(.appleMusic, status: .playing, becamePlayingAt: newer),
        ]
    )
    #expect(selected == .appleMusic)

    let nilIsOldest = selectActivePlayer(
        current: nil,
        activities: [
            activity(.spotify, status: .playing, becamePlayingAt: nil),
            activity(.appleMusic, status: .playing, becamePlayingAt: older),
        ]
    )
    #expect(nilIsOldest == .appleMusic)
}

@Test func selectActivePlayerFallsBackToNonPlayingCandidate() {
    let selected = selectActivePlayer(
        current: .spotify,
        activities: [
            activity(.spotify, running: false, status: .stopped),
            activity(.appleMusic, status: .paused, becamePlayingAt: Date(timeIntervalSince1970: 5)),
        ]
    )
    #expect(selected == .appleMusic)
}

@Test func selectActivePlayerReturnsNilWithoutCandidates() {
    let selected = selectActivePlayer(
        current: .spotify,
        activities: [
            activity(.spotify, running: false, hasTrack: true, status: .playing),
            activity(.appleMusic, running: true, hasTrack: false, status: .paused),
        ]
    )
    #expect(selected == nil)
    #expect(selectActivePlayer(current: nil, activities: []) == nil)
}

private func activity(
    _ player: PlayerID,
    running: Bool = true,
    hasTrack: Bool = true,
    status: PlaybackStatus,
    becamePlayingAt: Date? = nil
) -> PlayerActivity {
    PlayerActivity(
        player: player,
        isRunning: running,
        hasTrack: hasTrack,
        status: status,
        becamePlayingAt: becamePlayingAt
    )
}
