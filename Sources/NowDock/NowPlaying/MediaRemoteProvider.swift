import AppKit
import NowDockCore

final class MediaRemoteProvider: MediaProvider {
    let player: PlayerID = .system
    var onChange: (() -> Void)?

    // Seek: theos MediaRemote.h declares MRMediaRemoteCommandSeekToPlaybackPosition
    // and MRMediaRemoteSetElapsedTime(double). Shuffle/repeat keys and
    // ChangeShuffleMode/ChangeRepeatMode exist, but mode integers / userInfo are
    // unspecified; setShuffle/setRepeat stay no-ops and stay out of supported.
    static let supported: Set<PlayerCommand.Kind> = [
        .togglePlayPause, .next, .previous, .seek
    ]

    private static let commandToggle: UInt32 = 2
    private static let commandNext: UInt32 = 4
    private static let commandPrevious: UInt32 = 5

    private let lock = NSLock()
    private var snap = ProviderSnapshot.idle(supported: MediaRemoteProvider.supported)
    private var tokens: [NSObjectProtocol] = []
    private var started = false
    private let queue = DispatchQueue(label: "dev.nowdock.mediaremote", qos: .utility)
    private let symbols: Symbols?

    init() {
        symbols = Self.loadSymbols()
        if symbols == nil {
            snap = ProviderSnapshot.idle(supported: [])
        }
    }

    func start() {
        guard let symbols, !started else { return }
        started = true
        symbols.register(queue)
        if let name = symbols.didChangeName {
            tokens.append(
                NotificationCenter.default.addObserver(
                    forName: Notification.Name(name),
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    self?.queue.async { self?.fetch(then: nil) }
                }
            )
        }
        tokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.fetch(then: nil) }
            }
        )
        queue.async { [weak self] in self?.fetch(then: nil) }
    }

    func stop() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
        started = false
    }

    func snapshot() -> ProviderSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snap
    }

    func perform(_ command: PlayerCommand) async {
        guard let symbols else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                switch command {
                case .togglePlayPause:
                    _ = symbols.send(Self.commandToggle, nil)
                case .next:
                    _ = symbols.send(Self.commandNext, nil)
                case .previous:
                    _ = symbols.send(Self.commandPrevious, nil)
                case .seek(let seconds):
                    symbols.setElapsed?(max(0, seconds))
                    self.lock.lock()
                    self.snap.position = max(0, seconds)
                    self.snap.positionDate = Date()
                    self.lock.unlock()
                case .setShuffle, .setRepeat:
                    break
                }
                self.fetch {
                    continuation.resume()
                }
            }
        }
    }

    func refresh() async {
        guard symbols != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.fetch { continuation.resume() }
            }
        }
    }

    private func fetch(then done: (() -> Void)?) {
        guard let symbols else {
            done?()
            return
        }
        // Bind completions to @convention(block) locals first: passing a Swift
        // closure literal straight into the C function pointer crashes at runtime
        // ("closure argument passed as @noescape to Objective-C has escaped").
        let infoBlock: InfoBlock = { [weak self] dict in
            guard let self else {
                done?()
                return
            }
            self.apply(info: dict, keys: symbols.keys)
            let idBlock: DisplayIDBlock = { display in
                self.apply(displayID: display)
                self.emitChange()
                done?()
            }
            symbols.getDisplayID(self.queue, idBlock)
        }
        symbols.getInfo(queue, infoBlock)
    }

    private func apply(info dict: CFDictionary?, keys: InfoKeys) {
        lock.lock()
        defer { lock.unlock() }
        guard let dict else {
            snap.track = nil
            snap.status = .stopped
            snap.position = 0
            snap.positionDate = .distantPast
            snap.artworkData = nil
            snap.artworkID = nil
            return
        }
        let info = dict as NSDictionary
        let title = Self.stringify(info[keys.title]) ?? ""
        let artist = Self.stringify(info[keys.artist]) ?? ""
        let album = Self.stringify(info[keys.album])
        let context = Self.stringify(info[keys.queueName])
        let unique = Self.stringify(info[keys.unique])
        let duration = (info[keys.duration] as? NSNumber)?.doubleValue
        let elapsed = (info[keys.elapsed] as? NSNumber)?.doubleValue ?? 0
        let rate = (info[keys.rate] as? NSNumber)?.doubleValue
        let artwork = Self.artworkBytes(info[keys.artwork])
        let hasTrack = unique != nil || !title.isEmpty || !artist.isEmpty
        if hasTrack {
            let id = unique ?? "\(title)|\(artist)"
            snap.track = TrackInfo(
                id: id,
                title: title,
                artist: artist,
                album: album,
                context: context,
                duration: duration
            )
            if let rate, rate > 0 {
                snap.status = .playing
            } else if rate == 0 {
                snap.status = .paused
            } else {
                snap.status = .playing
            }
            snap.artworkData = artwork
            snap.artworkID = artwork == nil ? nil : id
        } else {
            snap.track = nil
            snap.status = .stopped
            snap.artworkData = nil
            snap.artworkID = nil
        }
        snap.position = max(0, elapsed)
        snap.positionDate = Date()
        snap.supported = Self.supported
    }

    private func apply(displayID: CFString?) {
        let bundle = displayID.map { $0 as String }
        let trimmed = bundle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = (trimmed?.isEmpty == false) ? trimmed : nil
        let name = usable.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName
        }
        lock.lock()
        snap.playerBundleID = usable
        snap.playerDisplayName = name
        lock.unlock()
    }

    private func emitChange() {
        Task { @MainActor [weak self] in
            self?.onChange?()
        }
    }

    private static func stringify(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func artworkBytes(_ value: Any?) -> Data? {
        switch value {
        case let data as Data:
            return data.isEmpty ? nil : data
        case let data as NSData:
            return data.length == 0 ? nil : data as Data
        default:
            return nil
        }
    }

    private static func loadSymbols() -> Symbols? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else { return nil }
        guard
            let getInfo: GetInfoFn = symbol(handle, "MRMediaRemoteGetNowPlayingInfo"),
            let register: RegisterFn = symbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications"),
            let send: SendFn = symbol(handle, "MRMediaRemoteSendCommand"),
            let getDisplayID: GetDisplayIDFn = symbol(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID")
        else { return nil }
        return Symbols(
            getInfo: getInfo,
            register: register,
            send: send,
            getDisplayID: getDisplayID,
            setElapsed: symbol(handle, "MRMediaRemoteSetElapsedTime"),
            keys: InfoKeys(handle: handle),
            didChangeName: cfString(handle, "kMRMediaRemoteNowPlayingInfoDidChangeNotification")
        )
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private static func cfString(_ handle: UnsafeMutableRawPointer, _ name: String) -> String? {
        guard let raw = dlsym(handle, name) else { return nil }
        guard let value = raw.load(as: CFString?.self) else { return nil }
        return value as String
    }

    private typealias InfoBlock = @convention(block) (CFDictionary?) -> Void
    private typealias DisplayIDBlock = @convention(block) (CFString?) -> Void
    private typealias GetInfoFn = @convention(c) (
        DispatchQueue,
        InfoBlock
    ) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendFn = @convention(c) (UInt32, CFDictionary?) -> DarwinBoolean
    private typealias GetDisplayIDFn = @convention(c) (
        DispatchQueue,
        DisplayIDBlock
    ) -> Void
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private struct Symbols {
        let getInfo: GetInfoFn
        let register: RegisterFn
        let send: SendFn
        let getDisplayID: GetDisplayIDFn
        let setElapsed: SetElapsedFn?
        let keys: InfoKeys
        let didChangeName: String?
    }

    private struct InfoKeys {
        let title: String
        let artist: String
        let album: String
        let duration: String
        let elapsed: String
        let rate: String
        let artwork: String
        let unique: String
        let queueName: String

        init(handle: UnsafeMutableRawPointer) {
            title = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoTitle") ?? "Title"
            artist = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoArtist") ?? "Artist"
            album = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoAlbum") ?? "Album"
            duration = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoDuration") ?? "Duration"
            elapsed = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoElapsedTime") ?? "ElapsedTime"
            rate = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoPlaybackRate") ?? "PlaybackRate"
            artwork = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoArtworkData") ?? "ArtworkData"
            unique = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoUniqueIdentifier") ?? "UniqueIdentifier"
            queueName = MediaRemoteProvider.cfString(handle, "kMRMediaRemoteNowPlayingInfoQueueName") ?? "QueueName"
        }
    }
}
