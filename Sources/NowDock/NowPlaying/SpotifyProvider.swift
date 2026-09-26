import AppKit
import NowDockCore

final class SpotifyProvider: MediaProvider {
    let player: PlayerID = .spotify
    var onChange: (() -> Void)?

    static let supported: Set<PlayerCommand.Kind> = [
        .togglePlayPause, .next, .previous, .seek, .shuffle, .repeatAll
    ]

    private let runner: AppleScriptRunner
    private let lock = NSLock()
    private var snap = ProviderSnapshot.idle(supported: SpotifyProvider.supported)
    private var observer: NSObjectProtocol?
    private var epoch = 0
    private var cachedArtworkURL: String?
    private var cachedArtworkData: Data?

    private let enrichScript = tellScript(.spotify, """
        set art to ""
        try
            if player state is not stopped then
                set art to artwork url of current track as text
            end if
        end try
        {shuffling, repeating, player position, art}
        """)

    private let bootstrapScript = tellScript(.spotify, """
        set theState to player state as text
        if player state is stopped then
            return {"", "", "", "", theState, 0, 0, shuffling, repeating, ""}
        end if
        {id of current track as text, name of current track, artist of current track, album of current track, theState, player position, duration of current track, shuffling, repeating, artwork url of current track as text}
        """)

    private let positionScript = tellScript(.spotify, "player position")

    init(runner: AppleScriptRunner = .shared) {
        self.runner = runner
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
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
        case .setShuffle(let on): body = "set shuffling to \(on)"
        case .setRepeat(.off): body = "set repeating to false"
        case .setRepeat(.all): body = "set repeating to true"
        case .setRepeat(.one): return
        }
        do {
            _ = try await runner.run(script: tellScript(.spotify, body), for: .spotify)
            lock.lock()
            switch command {
            case .setShuffle(let on): snap.shuffle = on
            case .setRepeat(.off): snap.repeatMode = .off
            case .setRepeat(.all): snap.repeatMode = .all
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
            let desc = try await runner.run(script: positionScript, for: .spotify)
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
            let list = try await runner.run(script: bootstrapScript, for: .spotify)
            let status = playbackStatus(from: list.atIndex(5)?.stringValue ?? "stopped")
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
                        duration: descriptorTime(list.atIndex(7))
                    )
                }
            }
            let shuffle = list.atIndex(8)?.booleanValue
            let repeating = list.atIndex(9)?.booleanValue ?? false
            let position = descriptorTime(list.atIndex(6))
            let artURL = list.atIndex(10)?.stringValue
            let now = Date()
            lock.lock()
            epoch += 1
            let token = epoch
            snap.track = track
            snap.status = status
            snap.position = position
            snap.positionDate = now
            snap.shuffle = shuffle
            snap.repeatMode = repeating ? .all : .off
            snap.permissionIssue = nil
            lock.unlock()
            onChange?()
            await applyArtwork(urlString: artURL, epoch: token)
        } catch RunnerError.playerNotRunning {
            return
        } catch {
            applyRunnerError(error)
        }
    }

    private func handle(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let parsed = NotificationParsing.parseSpotify(userInfo: userInfo) {
            let granted = runner.isAutomationGranted(for: player)
            lock.lock()
            epoch += 1
            snap.track = parsed.track
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
            let list = try await runner.run(script: enrichScript, for: .spotify)
            lock.lock()
            guard token == epoch else { lock.unlock(); return }
            snap.shuffle = list.atIndex(1)?.booleanValue
            snap.repeatMode = (list.atIndex(2)?.booleanValue ?? false) ? .all : .off
            snap.position = descriptorTime(list.atIndex(3))
            snap.positionDate = Date()
            snap.permissionIssue = nil
            let artURL = list.atIndex(4)?.stringValue
            lock.unlock()
            onChange?()
            await applyArtwork(urlString: artURL, epoch: token)
        } catch RunnerError.playerNotRunning {
            return
        } catch {
            applyRunnerError(error)
        }
    }

    private func applyArtwork(urlString: String?, epoch token: Int) async {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        if cachedArtworkURL == urlString, let data = cachedArtworkData {
            lock.lock()
            if token == epoch {
                snap.artworkData = data
                snap.artworkID = urlString
            }
            lock.unlock()
            onChange?()
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            cachedArtworkURL = urlString
            cachedArtworkData = data
            lock.lock()
            if token == epoch {
                snap.artworkData = data
                snap.artworkID = urlString
            }
            lock.unlock()
            onChange?()
        } catch {
            return
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

    private func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
