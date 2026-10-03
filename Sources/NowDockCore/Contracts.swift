import CoreGraphics
import Foundation

public enum PlayerID: String, Sendable, CaseIterable, Codable {
    case spotify
    case appleMusic
    /// Any player surfaced through the system MediaRemote service (browsers, VLC, etc.).
    case system

    public var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        case .system: ""
        }
    }

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Música"
        case .system: "Sistema"
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
}

public struct NowPlayingState: Equatable, Sendable {
    public var player: PlayerID?
    /// Friendly player name when `.system` (e.g. "VLC", "Google Chrome"). Nil otherwise.
    public var playerDisplayName: String?
    /// Bundle id of the `.system` player, for activation. Nil otherwise.
    public var playerBundleID: String?
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
        playerDisplayName: String? = nil,
        playerBundleID: String? = nil,
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
        self.playerDisplayName = playerDisplayName
        self.playerBundleID = playerBundleID
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

public enum PanelLayout: String, Sendable, Equatable, CaseIterable {
    /// Art, combined title line, progress with times, shuffle, previous, play, next, repeat.
    case full
    /// Art, combined title line, progress, previous, play, next.
    case compact
    /// Title and artist above previous, play, next. No art.
    case minimal

    /// Rendered-width cap. Beyond this the pill hugs the Dock side and stops growing.
    public static let maxWidth: CGFloat = 560

    /// The view scales its contents to fit both the width and Dock height.
    public static func layout(forWidth width: CGFloat) -> PanelLayout? {
        if width >= 400 { return .full }
        if width >= 280 { return .compact }
        if width >= 96 { return .minimal }
        return nil
    }
}

public enum EdgeGapPreset: String, Sendable, CaseIterable, Codable {
    case matchDock, small, medium, large

    /// Smallest clearance that still reads as separate from the Dock.
    /// Non-configurable safety invariant: `placement(for:)` clamps to it.
    public static let minimum: CGFloat = 12

    public func value(dockBottomInset: CGFloat) -> CGFloat {
        switch self {
        case .matchDock: max(Self.minimum, dockBottomInset)
        case .small: 12
        case .medium: 18
        case .large: 28
        }
    }
}

public struct PlacementInput: Equatable, Sendable {
    /// AppKit global coordinates. Origin is the bottom-left of the primary screen.
    public var screenFrame: CGRect
    public var dockFrame: CGRect
    /// Clearance between the pill's right edge and `dockFrame.minX`.
    /// Not a screen-edge margin, and not applied twice.
    public var dockGap: CGFloat

    public init(screenFrame: CGRect, dockFrame: CGRect, dockGap: CGFloat) {
        self.screenFrame = screenFrame
        self.dockFrame = dockFrame
        self.dockGap = dockGap
    }
}

public struct PlacedPanel: Equatable, Sendable {
    public let frame: CGRect
    public let layout: PanelLayout
}

public enum PlacementResult: Equatable, Sendable {
    case visible(PlacedPanel)
    case hidden
}
