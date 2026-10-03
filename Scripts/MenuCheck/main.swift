import AppKit
import Combine
import NowDockCore
import SwiftUI

@MainActor final class NowPlayingCenter: ObservableObject {
    @Published var state = NowPlayingState(player: .system, playerDisplayName: "Browser fixture", status: .paused, permissionIssues: [.automation(.appleMusic)])
    let installedPlayers: [PlayerID] = [.spotify, .appleMusic]
    var opened: [PlayerID] = []
    var requested: [PlayerID] = []
    func perform(_ command: PlayerCommand) {}
    func openPlayer(_ player: PlayerID) async throws { opened.append(player) }
    func requestAutomation(for player: PlayerID) async throws { requested.append(player) }
}

@MainActor final class CompanionWindowController: ObservableObject {
    @Published var layout: PanelLayout = .minimal
    @Published var isPanelVisible = false
    @Published var edgeGapPreset: EdgeGapPreset = .matchDock
}

@main struct MenuCheck {
    @MainActor static var captured: NSMenu?

    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let center = NowPlayingCenter()
        let controller = CompanionWindowController()
        let host = NSHostingView(rootView: CompanionView(center: center, window: controller))
        let panel = CompanionPanel()
        panel.setContent(host)
        panel.setFrame(CGRect(x: 6, y: 6, width: 193, height: 65), display: true)
        panel.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated {
                captured = menu
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { menu.cancelTracking() }
            }
        }
        defer { NotificationCenter.default.removeObserver(token); panel.orderOut(nil) }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 96, y: 32), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        host.rightMouseDown(with: event)
        guard let menu = captured else { fatalError("Production view did not present a native context menu") }
        for item in menu.items { print("ITEM \(item.title) enabled=\(item.isEnabled) state=\(item.state.rawValue)") }
        func item(_ title: String, in menu: NSMenu) -> NSMenuItem {
            guard let item = menu.items.first(where: { $0.title == title }) else { fatalError("Missing native menu item \(title)") }
            return item
        }
        func invoke(_ item: NSMenuItem) {
            precondition(item.isEnabled && item.action != nil, "Menu action disabled or missing")
            precondition(app.sendAction(item.action!, to: item.target, from: item), "Native menu action was not dispatched")
        }
        invoke(item("Abrir Spotify", in: menu))
        invoke(item("Abrir Música", in: menu))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(center.opened == [.spotify, .appleMusic], "Player labels and dispatched IDs disagree")
        print("PASS native menu open-player dispatch with unrelated active-player name")
        invoke(item("Ativar controle de Música…", in: menu))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(center.requested == [.appleMusic], "Automation action did not reach the requested player")
        print("PASS explicit Automation UI dispatch without a track")
        let submenu = item("Distância da Dock", in: menu).submenu!
        submenu.update()
        for (title, preset) in [("Igual à Dock", EdgeGapPreset.matchDock), ("Pequena", .small), ("Média", .medium), ("Grande", .large)] {
            invoke(item(title, in: submenu))
            precondition(controller.edgeGapPreset == preset, "Gap action selected the wrong preset")
            print("PASS gap UI dispatch \(preset.rawValue)")
        }
        _ = item("Abrir ao iniciar sessão", in: menu)
        _ = item("Sair do NowDock", in: menu)
        print("PASS login action present; service registration not invoked by this recording fixture")
        print("PASS complete native menu dispatch check")
        fflush(stdout)
        invoke(item("Sair do NowDock", in: menu))
        preconditionFailure("Quit menu action did not terminate the fixture")
    }
}
