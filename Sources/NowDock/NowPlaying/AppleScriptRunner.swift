import AppKit
import CoreServices
import NowDockCore

enum RunnerError: Error, Equatable {
    case playerNotRunning
    case automationDenied(PlayerID)
    case compileFailed
    case executeFailed(Int)
}

/// Serial AppleScript runner. Compile once per (player, source); never touches the main thread.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "dev.nowdock.applescript", qos: .utility)
    private var compiled: [Key: NSAppleScript] = [:]

    private struct Key: Hashable {
        let player: PlayerID
        let script: String
    }

    func isAutomationGranted(for player: PlayerID) -> Bool {
        permissionStatus(for: player) == noErr
    }

    func run(script: String, for player: PlayerID) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.runLocked(script: script, for: player))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runLocked(script: String, for player: PlayerID) throws -> NSAppleEventDescriptor {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier)
        guard !running.isEmpty else { throw RunnerError.playerNotRunning }

        if isAutomationDenied(for: player) {
            throw RunnerError.automationDenied(player)
        }

        let key = Key(player: player, script: script)
        let appleScript: NSAppleScript
        if let cached = compiled[key] {
            appleScript = cached
        } else {
            guard let created = NSAppleScript(source: script) else {
                throw RunnerError.compileFailed
            }
            var compileInfo: NSDictionary?
            guard created.compileAndReturnError(&compileInfo) else {
                if isDenied(compileInfo) { throw RunnerError.automationDenied(player) }
                throw RunnerError.compileFailed
            }
            compiled[key] = created
            appleScript = created
        }

        var executeInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&executeInfo)
        if let executeInfo {
            if isDenied(executeInfo) { throw RunnerError.automationDenied(player) }
            throw RunnerError.executeFailed(errorNumber(executeInfo) ?? 0)
        }
        return result
    }

    private func isAutomationDenied(for player: PlayerID) -> Bool {
        permissionStatus(for: player) == -1743
    }

    private func permissionStatus(for player: PlayerID) -> OSStatus {
        let bundle = player.bundleIdentifier
        guard !bundle.isEmpty else { return -1 }
        var address = AEAddressDesc()
        let created: OSErr = bundle.withCString { cstr in
            AECreateDesc(typeApplicationBundleID, cstr, bundle.utf8.count, &address)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&address) }
        return withUnsafePointer(to: &address) { ptr in
            AEDeterminePermissionToAutomateTarget(ptr, typeWildCard, typeWildCard, false)
        }
    }

    private func isDenied(_ info: NSDictionary?) -> Bool {
        errorNumber(info) == -1743
    }

    private func errorNumber(_ info: NSDictionary?) -> Int? {
        guard let value = info?[NSAppleScript.errorNumber] else { return nil }
        if let n = value as? Int { return n }
        return (value as? NSNumber)?.intValue
    }
}

func tellScript(_ player: PlayerID, _ body: String) -> String {
    """
    tell application id "\(player.bundleIdentifier)"
    \(body)
    end tell
    """
}

func descriptorTime(_ desc: NSAppleEventDescriptor?) -> TimeInterval {
    guard let desc else { return 0 }
    if let text = desc.stringValue, let value = Double(text) { return max(0, value) }
    return max(0, TimeInterval(desc.int32Value))
}

func playbackStatus(from raw: String) -> PlaybackStatus {
    switch raw.lowercased() {
    case "playing": return .playing
    case "paused": return .paused
    default: return .stopped
    }
}
