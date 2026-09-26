import Foundation

public struct ParsedNotification: Sendable {
    public var track: TrackInfo
    public var status: PlaybackStatus
    public var position: TimeInterval

    public init(track: TrackInfo, status: PlaybackStatus, position: TimeInterval) {
        self.track = track
        self.status = status
        self.position = position
    }
}

public enum NotificationParsing {
    public static func parseSpotify(userInfo: [AnyHashable: Any]) -> ParsedNotification? {
        parse(
            userInfo: userInfo,
            idKey: "Track ID",
            durationKey: "Duration",
            positionKey: "Playback Position"
        )
    }

    public static func parseAppleMusic(userInfo: [AnyHashable: Any]) -> ParsedNotification? {
        parse(
            userInfo: userInfo,
            idKey: "PersistentID",
            durationKey: "Total Time",
            positionKey: nil
        )
    }

    private static func parse(
        userInfo: [AnyHashable: Any],
        idKey: String,
        durationKey: String,
        positionKey: String?
    ) -> ParsedNotification? {
        guard let title = text(userInfo["Name"]), !title.isEmpty else {
            return nil
        }

        let durationMs = number(userInfo[durationKey])
        let track = TrackInfo(
            id: text(userInfo[idKey]) ?? "",
            title: title,
            artist: text(userInfo["Artist"]) ?? "",
            album: text(userInfo["Album"]),
            duration: durationMs.map { $0 / 1000 }
        )

        let position: TimeInterval
        if let positionKey, let value = number(userInfo[positionKey]) {
            position = value
        } else {
            position = 0
        }

        return ParsedNotification(
            track: track,
            status: playbackStatus(userInfo["Player State"]),
            position: position
        )
    }

    private static func playbackStatus(_ raw: Any?) -> PlaybackStatus {
        switch text(raw)?.lowercased() {
        case "playing": .playing
        case "paused": .paused
        case "stopped": .stopped
        default: .stopped
        }
    }

    private static func text(_ raw: Any?) -> String? {
        switch raw {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func number(_ raw: Any?) -> Double? {
        switch raw {
        case let value as NSNumber:
            return value.doubleValue
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}
