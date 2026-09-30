import AppKit
import NowDockCore
import SwiftUI

struct CompanionView: View {
    @ObservedObject private var center: NowPlayingCenter
    @ObservedObject private var window: CompanionWindowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(center: NowPlayingCenter, window: CompanionWindowController) {
        self.center = center
        self.window = window
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = LayoutMetrics(height: geo.size.height)
            Group {
                if center.state.isEmpty {
                    emptyState(metrics: metrics)
                } else {
                    playingState(metrics: metrics)
                }
            }
            .padding(.horizontal, metrics.pad)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .background(.regularMaterial)
        }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private func emptyState(metrics: LayoutMetrics) -> some View {
        let layout = window.layout
        switch layout {
        case .full:
            fullEmptyRow(metrics: metrics)
        case .compact:
            compactEmptyRow(metrics: metrics)
        case .minimal:
            minimalEmptyRow(metrics: metrics)
        }
    }

    @ViewBuilder
    private func playingState(metrics: LayoutMetrics) -> some View {
        let layout = window.layout
        switch layout {
        case .full:
            fullRow(metrics: metrics)
        case .compact:
            compactRow(metrics: metrics)
        case .minimal:
            minimalRow(metrics: metrics)
        }
    }

    @ViewBuilder
    private func fullEmptyRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
            Text("Nada tocando")
                .font(.system(size: metrics.title, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            openButton(metrics: metrics)
        }
    }

    @ViewBuilder
    private func compactEmptyRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
            Text("Nada tocando")
                .font(.system(size: metrics.title, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            openButton(metrics: metrics)
        }
    }

    @ViewBuilder
    private func minimalEmptyRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
            Spacer(minLength: 0)
            openButton(metrics: metrics)
        }
    }

    private func openButton(metrics: LayoutMetrics) -> some View {
        let players = center.installedPlayers
        return Group {
            if let first = players.first {
                Button("Abrir \(center.state.playerDisplayName ?? first.displayName)") {
                    center.openPlayer(first)
                }
                .buttonStyle(.plain)
                .font(.system(size: metrics.subtitle, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fullRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
                .onTapGesture(perform: openCurrentPlayer)
            VStack(alignment: .leading, spacing: metrics.gap * 0.35) {
                combinedTitle(metrics: metrics)
                progressRow(metrics: metrics, showTimes: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls(metrics: metrics, layout: .full)
        }
    }

    @ViewBuilder
    private func compactRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
                .onTapGesture(perform: openCurrentPlayer)
            VStack(alignment: .leading, spacing: metrics.gap * 0.35) {
                combinedTitle(metrics: metrics)
                progressRow(metrics: metrics, showTimes: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls(metrics: metrics, layout: .compact)
        }
    }

    @ViewBuilder
    private func minimalRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            VStack(alignment: .leading, spacing: metrics.gap * 0.35) {
                playingTitle(metrics: metrics)
                Text(subtitleLine)
                    .font(.system(size: metrics.subtitle))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls(metrics: metrics, layout: .minimal)
        }
    }

    private func playingTitle(metrics: LayoutMetrics) -> some View {
        Text(center.state.track?.title ?? "")
            .font(.system(size: metrics.title, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .onTapGesture(perform: openCurrentPlayer)
    }

    private func combinedTitle(metrics: LayoutMetrics) -> some View {
        let suffix = subtitleLine.isEmpty ? "" : " · \(subtitleLine)"
        return (Text(center.state.track?.title ?? "")
            .font(.system(size: metrics.title, weight: .semibold))
            .foregroundStyle(.primary)
            + Text(suffix)
            .font(.system(size: metrics.subtitle))
            .foregroundStyle(.secondary))
            .lineLimit(1)
            .onTapGesture(perform: openCurrentPlayer)
    }

    @ViewBuilder
    private func progressRow(metrics: LayoutMetrics, showTimes: Bool) -> some View {
        if center.state.status == .playing && window.isPanelVisible {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                seekRow(elapsed: center.state.elapsed(at: context.date), metrics: metrics, showTimes: showTimes)
            }
        } else {
            seekRow(elapsed: center.state.elapsed(at: .now), metrics: metrics, showTimes: showTimes)
        }
    }

    private func seekRow(elapsed: TimeInterval, metrics: LayoutMetrics, showTimes: Bool) -> some View {
        let duration = center.state.track?.duration
        let canSeek = center.state.supportedCommands.contains(.seek) && (duration ?? 0) > 0
        return HStack(spacing: metrics.gap * 0.5) {
            if showTimes {
                Text(Self.formatTime(elapsed))
                    .font(.system(size: metrics.time, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            SeekBar(
                elapsed: elapsed,
                duration: duration,
                barHeight: metrics.seek,
                enabled: canSeek
            ) { position in
                center.perform(.seek(position))
            }
            if showTimes {
                Text(Self.formatRemaining(elapsed: elapsed, duration: duration))
                    .font(.system(size: metrics.time, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func controls(metrics: LayoutMetrics, layout: PanelLayout) -> some View {
        let commands = center.state.supportedCommands
        HStack(spacing: metrics.gap * 0.4) {
            if layout == .full {
                ControlButton(
                    system: "shuffle",
                    size: metrics.button,
                    enabled: commands.contains(.shuffle),
                    emphasized: center.state.shuffle == true
                ) {
                    center.perform(.setShuffle(!(center.state.shuffle ?? false)))
                }
            }
            ControlButton(system: "backward.fill", size: metrics.button, enabled: commands.contains(.previous), compact: layout == .minimal) {
                center.perform(.previous)
            }
            playButton(metrics: metrics, enabled: commands.contains(.togglePlayPause))
            ControlButton(system: "forward.fill", size: metrics.button, enabled: commands.contains(.next), compact: layout == .minimal) {
                center.perform(.next)
            }
            if layout == .full {
                ControlButton(
                    system: center.state.repeatMode == .one ? "repeat.1" : "repeat",
                    size: metrics.button,
                    enabled: commands.contains(.repeatAll) || commands.contains(.repeatOne),
                    emphasized: (center.state.repeatMode ?? .off) != .off
                ) {
                    cycleRepeat()
                }
            }
        }
    }

    private func playButton(metrics: LayoutMetrics, enabled: Bool) -> some View {
        Button {
            center.perform(.togglePlayPause)
        } label: {
            ZStack {
                Circle().fill(.primary)
                Image(systemName: center.state.status == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: metrics.play, weight: .medium))
                    .foregroundStyle(.background)
            }
            .frame(width: metrics.playCircle, height: metrics.playCircle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func artworkTile(side: CGFloat) -> some View {
        ArtworkTile(artworkID: center.state.artworkID, data: center.state.artworkData, side: side)
            .id(center.state.artworkID ?? "placeholder")
            .transition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: center.state.artworkID)
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let player = center.state.player {
            Text("Tocando no \(center.state.playerDisplayName ?? player.displayName)")
        } else {
            Text("Nenhum player")
        }
        Divider()
        ForEach(center.installedPlayers, id: \.self) { id in
            Button("Abrir \(center.state.playerDisplayName ?? id.displayName)") {
                center.openPlayer(id)
            }
        }
        if !center.state.permissionIssues.isEmpty {
            Divider()
            Button("Permitir Automação…") {
                openPrefs("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            }
        }
        Divider()
        Menu("Folga da borda") {
            edgeGapButton("Igual à Dock", .matchDock)
            edgeGapButton("Pequena", .small)
            edgeGapButton("Média", .medium)
            edgeGapButton("Grande", .large)
        }
        Toggle("Abrir ao iniciar sessão", isOn: Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { LaunchAtLogin.setEnabled($0) }
        ))
        Divider()
        Button("Sair do NowDock") {
            NSApp.terminate(nil)
        }
    }

    private func edgeGapButton(_ title: String, _ preset: EdgeGapPreset) -> some View {
        Button {
            window.edgeGapPreset = preset
        } label: {
            if window.edgeGapPreset == preset {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var subtitleLine: String {
        guard let track = center.state.track else { return "" }
        let context = track.context ?? track.album
        if let context, !context.isEmpty {
            return "\(track.artist) — \(context)"
        }
        return track.artist
    }

    private func openCurrentPlayer() {
        guard let id = center.state.player else { return }
        center.openPlayer(id)
    }

    private func cycleRepeat() {
        let supportsOne = center.state.supportedCommands.contains(.repeatOne)
        let next: RepeatMode
        switch center.state.repeatMode ?? .off {
        case .off: next = .all
        case .all: next = supportsOne ? .one : .off
        case .one: next = .off
        }
        center.perform(.setRepeat(next))
    }

    private func openPrefs(_ spec: String) {
        guard let url = URL(string: spec) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func formatTime(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func formatRemaining(elapsed: TimeInterval, duration: TimeInterval?) -> String {
        let remaining = max(0, (duration ?? 0) - elapsed)
        let total = Int(remaining.rounded(.down))
        return String(format: "-%d:%02d", total / 60, total % 60)
    }
}

private struct LayoutMetrics {
    let height: CGFloat
    var pad: CGFloat { max(4, height * 0.1) }
    var art: CGFloat { max(20, height - pad * 2) }
    var title: CGFloat { max(10, height * 0.28) }
    var subtitle: CGFloat { max(8, height * 0.20) }
    var time: CGFloat { max(7, height * 0.16) }
    var play: CGFloat { max(14, height * 0.42) }
    var playCircle: CGFloat { max(20, height * 0.52) }
    var button: CGFloat { max(11, height * 0.30) }
    var seek: CGFloat { max(3, height * 0.06) }
    var gap: CGFloat { max(4, height * 0.08) }
}

private struct ArtworkTile: View {
    let artworkID: String?
    let data: Data?
    let side: CGFloat

    var body: some View {
        ZStack {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.08)
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.38, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.14, style: .continuous))
    }
}

private struct SeekBar: View {
    let elapsed: TimeInterval
    let duration: TimeInterval?
    let barHeight: CGFloat
    let enabled: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            let progress: CGFloat = {
                guard let duration, duration > 0 else { return 0 }
                return CGFloat(min(1, max(0, elapsed / duration)))
            }()
            let knob = barHeight * 2.2
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(barHeight, geo.size.width * progress))
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: knob, height: knob)
                    .shadow(radius: 1)
                    .offset(x: min(max(0, geo.size.width * progress - knob / 2), max(0, geo.size.width - knob)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(at: value.location.x, width: geo.size.width)
                    }
            )
        }
        .frame(height: barHeight)
        .allowsHitTesting(enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func seek(at x: CGFloat, width: CGFloat) {
        guard enabled, let duration, duration > 0, width > 0 else { return }
        let fraction = min(1, max(0, x / width))
        onSeek(duration * Double(fraction))
    }
}

private struct ControlButton: View {
    let system: String
    let size: CGFloat
    var enabled: Bool = true
    var emphasized: Bool = false
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(emphasized ? Color.accentColor : Color.primary)
                .frame(width: size * (compact ? 1.15 : 1.55), height: size * (compact ? 1.15 : 1.55))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
