import Foundation

public enum PlayerID: String, Sendable, CaseIterable, Codable {
    case spotify
    case appleMusic

    public var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Música"
        }
    }
}

public enum PlaybackStatus: String, Sendable, Equatable {
    case playing, paused, stopped
}

public enum RepeatMode: String, Sendable, Equatable, CaseIterable {
    case off, all, one
}

public struct TrackInfo: Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    /// Playlist or other playback context, when the player exposes it.
    public var context: String?
    public var duration: TimeInterval?

    public init(id: String, title: String, artist: String, album: String? = nil, context: String? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.context = context
        self.duration = duration
    }
}

public enum PlayerCommand: Hashable, Sendable {
    case togglePlayPause
    case next
    case previous
    case seek(TimeInterval)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)

    public enum Kind: Hashable, Sendable, CaseIterable {
        case togglePlayPause, next, previous, seek, shuffle, repeatAll, repeatOne
    }
}

public enum PermissionIssue: Hashable, Sendable {
    case automation(PlayerID)
    case accessibility
}

public struct NowPlayingState: Equatable, Sendable {
    public var player: PlayerID?
    public var track: TrackInfo?
    public var status: PlaybackStatus
    /// Position in seconds at `positionTimestamp`.
    public var position: TimeInterval
    public var positionTimestamp: Date
    public var shuffle: Bool?
    public var repeatMode: RepeatMode?
    public var artworkData: Data?
    /// Changes only when the artwork changes; views key image decoding on it.
    public var artworkID: String?
    public var supportedCommands: Set<PlayerCommand.Kind>
    public var permissionIssues: Set<PermissionIssue>

    public init(
        player: PlayerID? = nil,
        track: TrackInfo? = nil,
        status: PlaybackStatus = .stopped,
        position: TimeInterval = 0,
        positionTimestamp: Date = .distantPast,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil,
        artworkData: Data? = nil,
        artworkID: String? = nil,
        supportedCommands: Set<PlayerCommand.Kind> = [],
        permissionIssues: Set<PermissionIssue> = []
    ) {
        self.player = player
        self.track = track
        self.status = status
        self.position = position
        self.positionTimestamp = positionTimestamp
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.artworkData = artworkData
        self.artworkID = artworkID
        self.supportedCommands = supportedCommands
        self.permissionIssues = permissionIssues
    }

    public static let empty = NowPlayingState()

    public var isEmpty: Bool { track == nil }

    public func elapsed(at date: Date) -> TimeInterval {
        var value = position
        if status == .playing {
            value += max(0, date.timeIntervalSince(positionTimestamp))
        }
        if let duration = track?.duration, duration > 0 {
            value = min(value, duration)
        }
        return max(0, value)
    }
}

public enum PanelLayout: String, Sendable, Equatable {
    case full, compact, minimal
}

public enum EdgeGapPreset: String, Sendable, CaseIterable, Codable {
    /// Same distance the Dock keeps from the bottom of the screen (min 6 pt).
    case matchDock
    case small
    case medium
    case large

    public func value(dockBottomInset: CGFloat) -> CGFloat {
        switch self {
        case .matchDock: max(6, dockBottomInset)
        case .small: 6
        case .medium: 12
        case .large: 20
        }
    }
}

public struct PlacementInput: Equatable, Sendable {
    /// All rects in AppKit global coordinates (origin bottom-left of the primary screen).
    public var screenFrame: CGRect
    public var dockFrame: CGRect
    public var edgeGap: CGFloat
    public var maxWidth: CGFloat
    public var minWidth: CGFloat

    public init(screenFrame: CGRect, dockFrame: CGRect, edgeGap: CGFloat, maxWidth: CGFloat = 560, minWidth: CGFloat = 220) {
        self.screenFrame = screenFrame
        self.dockFrame = dockFrame
        self.edgeGap = edgeGap
        self.maxWidth = maxWidth
        self.minWidth = minWidth
    }
}

public enum PlacementResult: Equatable, Sendable {
    case visible(frame: CGRect, layout: PanelLayout)
    case hidden
}
