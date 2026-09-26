import AppKit
import CoreServices
import NowDockCore

final class AppleMusicProvider: MediaProvider {
    let player: PlayerID = .appleMusic
    var onChange: (() -> Void)?

    static let supported: Set<PlayerCommand.Kind> = [
        .togglePlayPause, .next, .previous, .seek, .shuffle, .repeatAll, .repeatOne
    ]

    private let runner: AppleScriptRunner
    private let lock = NSLock()
    private var snap = ProviderSnapshot.idle(supported: AppleMusicProvider.supported)
    private var observer: NSObjectProtocol?
    private var epoch = 0

    private let enrichScript = tellScript(.appleMusic, """
        set art to missing value
        set plist to ""
        try
            if player state is not stopped then
                if (count of artworks of current track) > 0 then
                    set art to raw data of artwork 1 of current track
                end if
                try
                    set plist to name of current playlist
                end try
            end if
        end try
        {shuffle enabled, song repeat as text, player position, plist, art}
        """)

    private let bootstrapScript = tellScript(.appleMusic, """
        set theState to player state as text
        set plist to ""
        set art to missing value
        if player state is stopped then
            return {"", "", "", "", theState, 0, 0, shuffle enabled, song repeat as text, plist, art}
        end if
        try
            set plist to name of current playlist
        end try
        try
            if (count of artworks of current track) > 0 then
                set art to raw data of artwork 1 of current track
            end if
        end try
        {persistent ID of current track as text, name of current track, artist of current track, album of current track, theState, player position, duration of current track, shuffle enabled, song repeat as text, plist, art}
        """)

    private let positionScript = tellScript(.appleMusic, "player position")

    init(runner: AppleScriptRunner = .shared) {
        self.runner = runner
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handle(notification)
        }
        Task { await self.pullIfRunning() }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    func snapshot() -> ProviderSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snap
    }

    func perform(_ command: PlayerCommand) async {
        let body: String
        switch command {
        case .togglePlayPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let seconds): body = "set player position to \(seconds)"
        case .setShuffle(let on): body = "set shuffle enabled to \(on)"
        case .setRepeat(let mode): body = "set song repeat to \(musicRepeatToken(mode))"
        }
        do {
            _ = try await runner.run(script: tellScript(.appleMusic, body), for: .appleMusic)
            lock.lock()
            switch command {
            case .setShuffle(let on): snap.shuffle = on
            case .setRepeat(let mode): snap.repeatMode = mode
            case .seek(let seconds):
                snap.position = max(0, seconds)
                snap.positionDate = Date()
            default: break
            }
            snap.permissionIssue = nil
            lock.unlock()
            onChange?()
        } catch {
            applyRunnerError(error)
        }
    }

    func refreshPosition() async {
        guard runner.isAutomationGranted(for: player) else { return }
        do {
            let desc = try await runner.run(script: positionScript, for: .appleMusic)
            let now = Date()
            lock.lock()
            snap.position = descriptorTime(desc)
            snap.positionDate = now
            snap.permissionIssue = nil
            lock.unlock()
        } catch RunnerError.playerNotRunning {
            return
        } catch {
            applyRunnerError(error)
        }
    }

    func pullIfRunning() async {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
        guard running else { return }
        guard runner.isAutomationGranted(for: player) else {
            markAutomationNeededIfTrackPresent()
            return
        }
        do {
            let list = try await runner.run(script: bootstrapScript, for: .appleMusic)
            let status = playbackStatus(from: list.atIndex(5)?.stringValue ?? "stopped")
            let context = playlistContext(list.atIndex(10)?.stringValue)
            let track: TrackInfo?
            if status == .stopped {
                track = nil
            } else {
                let id = list.atIndex(1)?.stringValue ?? ""
                let title = list.atIndex(2)?.stringValue ?? ""
                if id.isEmpty && title.isEmpty {
                    track = nil
                } else {
                    track = TrackInfo(
                        id: id.isEmpty ? title : id,
                        title: title,
                        artist: list.atIndex(3)?.stringValue ?? "",
                        album: emptyToNil(list.atIndex(4)?.stringValue),
                        context: context,
                        duration: descriptorTime(list.atIndex(7))
                    )
                }
            }
            let now = Date()
            let art = artworkData(list.atIndex(11))
            lock.lock()
            epoch += 1
            snap.track = track
            snap.status = status
            snap.position = descriptorTime(list.atIndex(6))
            snap.positionDate = now
            snap.shuffle = list.atIndex(8)?.booleanValue
            snap.repeatMode = parseRepeat(list.atIndex(9)?.stringValue)
            snap.artworkData = art
            snap.artworkID = art == nil ? nil : track?.id
            snap.permissionIssue = nil
            lock.unlock()
            onChange?()
        } catch RunnerError.playerNotRunning {
            return
        } catch {
            applyRunnerError(error)
        }
    }

    private func handle(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let parsed = NotificationParsing.parseAppleMusic(userInfo: userInfo) {
            let granted = runner.isAutomationGranted(for: player)
            lock.lock()
            epoch += 1
            var track = parsed.track
            track.context = snap.track?.id == track.id ? snap.track?.context : nil
            snap.track = track
            snap.status = parsed.status
            snap.position = parsed.position
            snap.positionDate = Date()
            if parsed.track != nil && !granted {
                snap.permissionIssue = .automation(player)
            } else {
                snap.permissionIssue = nil
            }
            lock.unlock()
            onChange?()
        }
        Task { await self.enrich() }
    }

    private func enrich() async {
        guard runner.isAutomationGranted(for: player) else {
            markAutomationNeededIfTrackPresent()
            return
        }
        lock.lock()
        epoch += 1
        let token = epoch
        lock.unlock()
        do {
            let list = try await runner.run(script: enrichScript, for: .appleMusic)
            let context = playlistContext(list.atIndex(4)?.stringValue)
            let art = artworkData(list.atIndex(5))
            lock.lock()
            guard token == epoch else { lock.unlock(); return }
            snap.shuffle = list.atIndex(1)?.booleanValue
            snap.repeatMode = parseRepeat(list.atIndex(2)?.stringValue)
            snap.position = descriptorTime(list.atIndex(3))
            snap.positionDate = Date()
            if var track = snap.track {
                track.context = context
                snap.track = track
                snap.artworkID = art == nil ? nil : track.id
            }
            snap.artworkData = art
            snap.permissionIssue = nil
            lock.unlock()
            onChange?()
        } catch RunnerError.playerNotRunning {
            return
        } catch {
            applyRunnerError(error)
        }
    }

    private func markAutomationNeededIfTrackPresent() {
        lock.lock()
        let hasTrack = snap.track != nil
        if hasTrack {
            snap.permissionIssue = .automation(player)
        }
        lock.unlock()
        if hasTrack { onChange?() }
    }

    private func applyRunnerError(_ error: Error) {
        guard let denied = error as? RunnerError, case .automationDenied(let id) = denied else { return }
        lock.lock()
        snap.permissionIssue = .automation(id)
        lock.unlock()
        onChange?()
    }

    private func parseRepeat(_ raw: String?) -> RepeatMode? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off": return .off
        case "one": return .one
        case "all": return .all
        default: return nil
        }
    }

    private func musicRepeatToken(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: return "off"
        case .one: return "one"
        case .all: return "all"
        }
    }

    private func playlistContext(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        switch trimmed.lowercased() {
        case "library", "biblioteca", "music library", "biblioteca de músicas":
            return nil
        default:
            return trimmed
        }
    }

    private func artworkData(_ desc: NSAppleEventDescriptor?) -> Data? {
        guard let desc, desc.descriptorType != typeNull else { return nil }
        let data = desc.data
        return data.isEmpty ? nil : data
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
