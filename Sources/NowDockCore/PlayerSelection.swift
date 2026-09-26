import Foundation

public struct PlayerActivity: Sendable {
    public var player: PlayerID
    public var isRunning: Bool
    public var hasTrack: Bool
    public var status: PlaybackStatus
    public var becamePlayingAt: Date?

    public init(
        player: PlayerID,
        isRunning: Bool,
        hasTrack: Bool,
        status: PlaybackStatus,
        becamePlayingAt: Date?
    ) {
        self.player = player
        self.isRunning = isRunning
        self.hasTrack = hasTrack
        self.status = status
        self.becamePlayingAt = becamePlayingAt
    }
}

public func selectActivePlayer(current: PlayerID?, activities: [PlayerActivity]) -> PlayerID? {
    let candidates = activities.filter { $0.isRunning && $0.hasTrack }
    if let current, candidates.contains(where: { $0.player == current }) {
        return current
    }

    let playing = candidates.filter { $0.status == .playing }
    if let player = newest(playing) {
        return player
    }
    return newest(candidates)
}

private func newest(_ activities: [PlayerActivity]) -> PlayerID? {
    activities.max { lhs, rhs in
        switch (lhs.becamePlayingAt, rhs.becamePlayingAt) {
        case let (left?, right?): left < right
        case (nil, .some): true
        case (.some, nil): false
        case (nil, nil): false
        }
    }?.player
}
