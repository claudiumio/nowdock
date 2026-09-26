import Foundation
import NowDockCore

struct ProviderSnapshot {
    var track: TrackInfo?
    var status: PlaybackStatus
    var position: TimeInterval
    var positionDate: Date
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    var artworkData: Data?
    var artworkID: String?
    var supported: Set<PlayerCommand.Kind>
    var permissionIssue: PermissionIssue?
    var playerDisplayName: String? = nil
    var playerBundleID: String? = nil

    static func idle(supported: Set<PlayerCommand.Kind>) -> ProviderSnapshot {
        ProviderSnapshot(
            track: nil,
            status: .stopped,
            position: 0,
            positionDate: .distantPast,
            shuffle: nil,
            repeatMode: nil,
            artworkData: nil,
            artworkID: nil,
            supported: supported,
            permissionIssue: nil,
            playerDisplayName: nil,
            playerBundleID: nil
        )
    }
}

protocol MediaProvider: AnyObject {
    var player: PlayerID { get }
    func start()
    func stop()
    func snapshot() -> ProviderSnapshot
    func perform(_ command: PlayerCommand) async
    var onChange: (() -> Void)? { get set }
}
