import AppKit
import NowDockCore
@testable import NowDock

@main
struct NativeCheck {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let mode = CommandLine.arguments[1]
        let screen = DockGeometry.snapshot().screenFrame
        if mode == "login" {
            precondition(Bundle.main.bundleIdentifier == "dev.nowdock.LoginCheck", "Login service test must use its isolated bundle")
            let before = LaunchAtLogin.status
            precondition(before != .enabled && before != .requiresApproval, "Isolated login bundle was already registered")
            defer { try? LaunchAtLogin.setEnabled(false) }
            try LaunchAtLogin.setEnabled(true)
            let registered = LaunchAtLogin.status
            precondition(registered == .enabled || registered == .requiresApproval, "Login service did not register")
            print("PASS native login registration status=\(registered.rawValue)")
            try LaunchAtLogin.setEnabled(false)
            precondition(LaunchAtLogin.status != .enabled && LaunchAtLogin.status != .requiresApproval, "Login service was not removed")
            print("PASS native login unregistration and restoration")
            return
        }
        if mode == "safety" {
            let defaults = UserDefaults.standard
            let saved = defaults.object(forKey: "edgeGapPreset")
            defer {
                if let saved { defaults.set(saved, forKey: "edgeGapPreset") }
                else { defaults.removeObject(forKey: "edgeGapPreset") }
            }
            let placement = CompanionWindowController()
            for preset in EdgeGapPreset.allCases {
                placement.edgeGapPreset = preset
                precondition(CompanionWindowController().edgeGapPreset == preset, "Gap preference did not survive controller recreation")
                print("PASS gap persistence \(preset.rawValue)")
            }
            let center = NowPlayingCenter()
            for id in [PlayerID.appleMusic, .spotify] {
                let before = NSRunningApplication.runningApplications(withBundleIdentifier: id.bundleIdentifier)
                if before.isEmpty {
                    do {
                        try await center.requestAutomation(for: id)
                        preconditionFailure("Closed player accepted an Automation command")
                    } catch RunnerError.playerNotRunning {
                        precondition(NSRunningApplication.runningApplications(withBundleIdentifier: id.bundleIdentifier).isEmpty, "Automation request launched a closed player")
                        print("PASS closed-player Automation safety \(id.rawValue)")
                    }
                } else {
                    print("SKIP closed-player safety \(id.rawValue) already running")
                }
            }
            for provider: MediaProvider in [AppleMusicProvider(), SpotifyProvider()] {
                let id = provider.player
                guard !AppleScriptRunner.shared.isAutomationGranted(for: id), !NSRunningApplication.runningApplications(withBundleIdentifier: id.bundleIdentifier).isEmpty else {
                    print("SKIP missing-permission startup \(id.rawValue)")
                    continue
                }
                if let music = provider as? AppleMusicProvider { await music.pullIfRunning() }
                if let spotify = provider as? SpotifyProvider { await spotify.pullIfRunning() }
                let snapshot = provider.snapshot()
                precondition(snapshot.track == nil && snapshot.permissionIssue == .automation(id), "Missing permission was hidden when no track existed")
                print("PASS empty startup exposes Automation \(id.rawValue)")
            }
            return
        }
        if mode == "fixture" {
            let window = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.alphaValue = 0.01
            window.ignoresMouseEvents = true
            window.setFrame(screen, display: true)
            window.orderBack(nil)
            print("READY \(getpid())")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { app.terminate(nil) }
            app.run()
            return
        }
        if mode == "inventory" {
            let expected = Int(CommandLine.arguments[2])!
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let present = windows.contains { row in
                guard row[kCGWindowOwnerPID as String] as? Int == expected,
                      row[kCGWindowLayer as String] as? Int == 0,
                      let bounds = row[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                return abs(rect.width - screen.width) < 8 && abs(rect.height - screen.height) < 8
                    && abs(rect.minX - screen.minX) < 8 && abs(rect.minY - screen.minY) < 8
            }
            print(present ? "PRESENT" : "ABSENT")
            return
        }
        let monitor = FullscreenMonitor()
        monitor.screenFrame = { screen }
        var fullscreen = false
        monitor.isFullscreen = { fullscreen = $0 }
        monitor.evaluate()
        let expectFullscreen = mode == "baseline" ? fullscreen : mode == "fullscreen"
        precondition(fullscreen == expectFullscreen, "Fullscreen fixture did not match the expected detector state")
        let controller = CompanionWindowController()
        controller.setContentView(NSView())
        controller.start()
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(controller.isPanelVisible == !expectFullscreen, "Panel startup visibility disagrees with fullscreen")
        for window in app.windows { window.orderOut(nil) }
        print("PASS startup fullscreen=\(fullscreen) visible=\(controller.isPanelVisible)")
    }
}
