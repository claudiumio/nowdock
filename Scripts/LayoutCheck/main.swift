import AppKit
import Combine
import NowDockCore
import SwiftUI

// Test fixtures drive the production view without starting or controlling a player.
@MainActor
final class NowPlayingCenter: ObservableObject {
    @Published var state = NowPlayingState(
        player: .appleMusic,
        track: TrackInfo(id: "layout-check", title: "A long track title for the layout check", artist: "An artist with a long name", duration: 240),
        status: .paused,
        supportedCommands: Set(PlayerCommand.Kind.allCases)
    )
    let installedPlayers: [PlayerID] = [.appleMusic]
    func perform(_ command: PlayerCommand) {}
    func openPlayer(_ player: PlayerID) async throws {}
    func requestAutomation(for player: PlayerID) async throws {}
}

@MainActor
final class CompanionWindowController: ObservableObject {
    @Published var layout: PanelLayout = .minimal
    @Published var isPanelVisible = false
    var edgeGapPreset: EdgeGapPreset = .matchDock
}

struct Sample {
    let width: CGFloat
    let height: CGFloat
    var delay: TimeInterval = 0.03
    var visible = false
    var shortTitle = false
    var label: String = ""
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let center = NowPlayingCenter()
    let controller = CompanionWindowController()
    let host = NSHostingView(rootView: CompanionView(center: center, window: controller)
        .clipShape(Capsule()))
    host.sizingOptions = []
    host.appearance = NSAppearance(named: .darkAqua)
    let panel = CompanionPanel()
    panel.setContent(host)
    let motion = CommandLine.arguments.contains("--motion")
    let samples: [Sample] = motion ? [
        Sample(width: 113.5, height: 65, delay: 0.05, visible: true, label: "t=0.05 entry"),
        Sample(width: 113.5, height: 65, delay: 1, visible: true, label: "t=1.05"),
        Sample(width: 113.5, height: 65, delay: 2, visible: true, label: "t=3.05"),
        Sample(width: 113.5, height: 65, delay: 4, visible: true, label: "t=7.05"),
        Sample(width: 113.5, height: 65, delay: 12, visible: true, label: "t=19.05 stopped"),
        Sample(width: 113.5, height: 65, delay: 1, visible: true, label: "t=20.05 stopped"),
        Sample(width: 113.5, height: 65, label: "hidden"),
        Sample(width: 113.5, height: 65, delay: 1, label: "hidden +1s"),
        Sample(width: 113.5, height: 65, visible: true, shortTitle: true, label: "short title"),
        Sample(width: 113.5, height: 65, delay: 1, visible: true, shortTitle: true, label: "short title +1s"),
    ] : [CGFloat(32), 48, 65, 96, 160].flatMap { height in
        [CGFloat(96), 113.5, 279, 280, 399, 400, 560].map { Sample(width: $0, height: height) }
    }
    let rowHeight = 196
    let image = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 620, pixelsHigh: rowHeight * samples.count,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    var frames: [Data] = []
    for (row, sample) in samples.enumerated() {
        guard let layout = PanelLayout.layout(forWidth: sample.width) else { fatalError("Missing layout") }
        controller.layout = layout
        controller.isPanelVisible = sample.visible
        if sample.shortTitle { center.state.track?.title = "Short" }
        host.rootView = CompanionView(center: center, window: controller).clipShape(Capsule())
        panel.setFrame(CGRect(x: 6, y: 6, width: sample.width, height: sample.height), display: true)
        panel.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(sample.delay))
        host.layoutSubtreeIfNeeded()
        let snapshot = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: snapshot)
        frames.append(snapshot.representation(using: .png, properties: [:])!)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        let y = CGFloat(image.pixelsHigh - (row + 1) * rowHeight)
        NSColor.windowBackgroundColor.setFill()
        CGRect(x: 0, y: y, width: 620, height: CGFloat(rowHeight)).fill()
        let label = "\(sample.width) x \(sample.height)  \(layout.rawValue)  \(sample.label)"
        label.draw(at: CGPoint(x: 12, y: y + 176), withAttributes: [.foregroundColor: NSColor.labelColor])
        snapshot.draw(in: CGRect(x: 12, y: y + 8, width: sample.width, height: sample.height))
        NSGraphicsContext.restoreGraphicsState()
        print("RENDER \(label)")
    }
    if motion {
        precondition(frames[1] != frames[2], "Title did not move")
        precondition(frames[4] == frames[5], "Title kept moving after its finite pass")
        precondition(frames[4] == frames[6], "Title did not return to its static rendered text")
        precondition(frames[6] == frames[7], "Hidden panel still animated")
        precondition(frames[8] == frames[9], "Fitting title still animated")
        print("PASS title motion, finite stop, hidden panel, and fitting title")
        let text = "A long track title for the layout check"
        let reduced = NSHostingView(rootView: ScrollingTitle(
            content: Text(text).font(.system(size: 12)), label: text,
            isVisible: true, reduceMotion: true
        ))
        reduced.sizingOptions = []
        panel.setContent(reduced)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        func snapshotReduced() -> Data {
            reduced.layoutSubtreeIfNeeded()
            let bitmap = reduced.bitmapImageRepForCachingDisplay(in: reduced.bounds)!
            reduced.cacheDisplay(in: reduced.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        let before = snapshotReduced()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(snapshotReduced() == before, "Reduce Motion still animated")
        reduced.rootView = ScrollingTitle(content: Text(""), label: "", isVisible: true, reduceMotion: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(snapshotReduced() != before, "Reduce Motion title was empty")
        print("PASS Reduce Motion preserves a visible static title")
    }
    panel.orderOut(nil)
    let output = CommandLine.arguments[1]
    try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("Rendered \(samples.count) production SwiftUI layouts with synthetic track data to \(output)")
}
