import AppKit
import Combine
import NowDockCore
import os

@MainActor
final class NowPlayingCenter: ObservableObject {
    @Published private(set) var state: NowPlayingState = .empty

    var isProgressActive = false {
        didSet {
            guard oldValue != isProgressActive else { return }
            if isProgressActive {
                if state.status == .playing {
                    refreshPositionTimestamp()
                    startResyncTimer()
                }
            } else {
                invalidateResyncTimer()
            }
        }
    }

    var installedPlayers: [PlayerID] {
        PlayerID.allCases.filter(isInstalled)
    }

    private let spotify = SpotifyProvider()
    private let music = AppleMusicProvider()
    private let system = MediaRemoteProvider()
    private var workspaceTokens: [NSObjectProtocol] = []
    private var resyncTimer: Timer?
    private var becamePlayingAt: [PlayerID: Date] = [:]
    private var lastStatus: [PlayerID: PlaybackStatus] = [:]
    private var lastLoggedTrackID: String?
    private var didStart = false

    init() {}

    func start() {
        guard !didStart else { return }
        didStart = true

        spotify.onChange = { [weak self] in
            Task { @MainActor in self?.providerDidChange() }
        }
        music.onChange = { [weak self] in
            Task { @MainActor in self?.providerDidChange() }
        }
        system.onChange = { [weak self] in
            Task { @MainActor in self?.providerDidChange() }
        }
        spotify.start()
        music.start()
        system.start()
        watchWorkspace()
        publish()
    }

    func perform(_ command: PlayerCommand) {
        guard let player = state.player else { return }
        // Shuffle/repeat are borrowed from legacy when the system client is
        // Spotify/Music, so route them back to the owning provider.
        let target: MediaProvider
        switch command {
        case .setShuffle, .setRepeat:
            if player == .system, let bundle = state.playerBundleID {
                target = bundle == PlayerID.spotify.bundleIdentifier ? spotify
                    : bundle == PlayerID.appleMusic.bundleIdentifier ? music
                    : provider(for: player)
            } else {
                target = provider(for: player)
            }
        default:
            target = provider(for: player)
        }
        Task {
            await target.perform(command)
            await MainActor.run { [weak self] in
                self?.publish()
            }
        }
    }

    func openPlayer(_ id: PlayerID) {
        let bundle: String
        switch id {
        case .system:
            guard let systemBundle = state.playerBundleID, !systemBundle.isEmpty else { return }
            bundle = systemBundle
        case .spotify, .appleMusic:
            bundle = id.bundleIdentifier
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    private func providerDidChange() {
        publish()
    }

    private func publish() {
        let spotifySnap = spotify.snapshot()
        let musicSnap = music.snapshot()
        let systemSnap = system.snapshot()
        let snapshots: [(PlayerID, ProviderSnapshot)] = [(.spotify, spotifySnap), (.appleMusic, musicSnap)]

        var issues = Set<PermissionIssue>()
        if let issue = spotifySnap.permissionIssue { issues.insert(issue) }
        if let issue = musicSnap.permissionIssue { issues.insert(issue) }
        if let issue = systemSnap.permissionIssue { issues.insert(issue) }

        var activities: [PlayerActivity] = []
        for (id, snap) in snapshots {
            let running = isRunning(id)
            noteTransition(id, status: running ? snap.status : .stopped, running: running)
            activities.append(
                PlayerActivity(
                    player: id,
                    isRunning: running,
                    hasTrack: running && snap.track != nil,
                    status: running ? snap.status : .stopped,
                    becamePlayingAt: running ? becamePlayingAt[id] : nil
                )
            )
        }

        let systemHasTrack = systemSnap.track != nil
        noteTransition(.system, status: systemHasTrack ? systemSnap.status : .stopped, running: systemHasTrack)
        activities.append(
            PlayerActivity(
                player: .system,
                isRunning: systemHasTrack,
                hasTrack: systemHasTrack,
                status: systemHasTrack ? systemSnap.status : .stopped,
                becamePlayingAt: systemHasTrack ? becamePlayingAt[.system] : nil
            )
        )

        if systemHasTrack {
            // MediaRemote exposes no shuffle/repeat; borrow them from the legacy
            // provider when the system client is Spotify/Music. A non-nil legacy
            // value proves Automation is granted (enrichment is gated), so merging
            // never triggers a consent prompt speculatively.
            let legacy: ProviderSnapshot? = {
                switch systemSnap.playerBundleID {
                case PlayerID.spotify.bundleIdentifier: spotifySnap
                case PlayerID.appleMusic.bundleIdentifier: musicSnap
                default: nil
                }
            }()
            var shuffle = systemSnap.shuffle
            var repeatMode = systemSnap.repeatMode
            var supported = systemSnap.supported
            if shuffle == nil, let value = legacy?.shuffle {
                shuffle = value
                supported.insert(.shuffle)
            }
            if repeatMode == nil, let value = legacy?.repeatMode {
                repeatMode = value
                supported.insert(.repeatAll)
                if legacy?.supported.contains(.repeatOne) == true {
                    supported.insert(.repeatOne)
                }
            }
            state = NowPlayingState(
                player: .system,
                playerDisplayName: systemSnap.playerDisplayName,
                playerBundleID: systemSnap.playerBundleID,
                track: systemSnap.track,
                status: systemSnap.status,
                position: systemSnap.position,
                positionTimestamp: systemSnap.positionDate,
                shuffle: shuffle,
                repeatMode: repeatMode,
                artworkData: systemSnap.artworkData,
                artworkID: systemSnap.artworkID,
                supportedCommands: supported,
                permissionIssues: issues
            )
        } else if let selected = selectActivePlayer(current: state.player, activities: activities),
                  selected != .system,
                  let snap = snapshots.first(where: { $0.0 == selected })?.1,
                  isRunning(selected) {
            state = NowPlayingState(
                player: selected,
                playerDisplayName: snap.playerDisplayName,
                playerBundleID: snap.playerBundleID,
                track: snap.track,
                status: snap.status,
                position: snap.position,
                positionTimestamp: snap.positionDate,
                shuffle: snap.shuffle,
                repeatMode: snap.repeatMode,
                artworkData: snap.artworkData,
                artworkID: snap.artworkID,
                supportedCommands: snap.supported,
                permissionIssues: issues
            )
        } else {
            state = NowPlayingState(permissionIssues: issues)
        }
        if state.track?.id != lastLoggedTrackID {
            lastLoggedTrackID = state.track?.id
            if let track = state.track {
                let player = state.playerDisplayName ?? state.player?.displayName ?? "?"
                Logger.nowDockPlaying.info("now playing \"\(track.title, privacy: .public)\" — \(track.artist, privacy: .public) (\(player, privacy: .public))")
            } else {
                Logger.nowDockPlaying.info("now playing cleared")
            }
        }
        syncResyncTimer()
    }

    private func noteTransition(_ id: PlayerID, status: PlaybackStatus, running: Bool) {
        if !running {
            becamePlayingAt[id] = nil
            lastStatus[id] = .stopped
            return
        }
        if status == .playing && lastStatus[id] != .playing {
            becamePlayingAt[id] = Date()
        }
        lastStatus[id] = status
    }

    private func watchWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let bundle = app.bundleIdentifier,
                    bundle == PlayerID.spotify.bundleIdentifier || bundle == PlayerID.appleMusic.bundleIdentifier
                else { return }
                Task { @MainActor in
                    await self?.handleWorkspace(name: name, bundle: bundle)
                }
            }
            workspaceTokens.append(token)
        }
    }

    private func handleWorkspace(name: Notification.Name, bundle: String) async {
        let id: PlayerID? = bundle == PlayerID.spotify.bundleIdentifier
            ? .spotify
            : bundle == PlayerID.appleMusic.bundleIdentifier ? .appleMusic : nil
        guard let id else { return }
        if name == NSWorkspace.didLaunchApplicationNotification {
            await pullIfRunning(id)
        } else {
            becamePlayingAt[id] = nil
            lastStatus[id] = .stopped
        }
        publish()
    }

    private func refreshPositionTimestamp() {
        let now = Date()
        var next = state
        next.position = state.elapsed(at: now)
        next.positionTimestamp = now
        state = next
    }

    private func syncResyncTimer() {
        if isProgressActive && state.status == .playing {
            startResyncTimer()
        } else {
            invalidateResyncTimer()
        }
    }

    private func startResyncTimer() {
        guard resyncTimer == nil else { return }
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { await self?.resyncPosition() }
        }
    }

    private func invalidateResyncTimer() {
        resyncTimer?.invalidate()
        resyncTimer = nil
    }

    private func resyncPosition() async {
        guard isProgressActive, state.status == .playing, let player = state.player else { return }
        await refreshPosition(player)
        publish()
    }

    private func provider(for id: PlayerID) -> MediaProvider {
        switch id {
        case .spotify: return spotify
        case .appleMusic: return music
        case .system: return system
        }
    }

    private func pullIfRunning(_ id: PlayerID) async {
        switch id {
        case .spotify: await spotify.pullIfRunning()
        case .appleMusic: await music.pullIfRunning()
        case .system: await system.refresh()
        }
    }

    private func refreshPosition(_ id: PlayerID) async {
        switch id {
        case .spotify: await spotify.refreshPosition()
        case .appleMusic: await music.refreshPosition()
        case .system: await system.refresh()
        }
    }

    private func isRunning(_ id: PlayerID) -> Bool {
        let bundle = id.bundleIdentifier
        guard !bundle.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    private func isInstalled(_ id: PlayerID) -> Bool {
        let names: [String]
        switch id {
        case .spotify:
            names = [id.displayName, "Spotify"]
        case .appleMusic:
            names = [id.displayName, "Music", "Música"]
        case .system:
            names = []
        }
        return names.contains { NSWorkspace.shared.fullPath(forApplication: $0) != nil }
    }
}
