import AppKit
import NowDockCore
import SwiftUI

struct CompanionView: View {
    @ObservedObject private var center: NowPlayingCenter
    @ObservedObject private var window: CompanionWindowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requestingAutomation = false
    @State private var loginStatus = LaunchAtLogin.status

    init(center: NowPlayingCenter, window: CompanionWindowController) {
        self.center = center
        self.window = window
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = LayoutMetrics(width: geo.size.width, height: geo.size.height, layout: window.layout)
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
        .contextMenu {
            contextMenu.onAppear { loginStatus = LaunchAtLogin.status }
        }
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
                .minimumScaleFactor(0.75)
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
                .minimumScaleFactor(0.75)
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
                Button(window.layout == .minimal ? "Abrir" : "Abrir \(first.displayName)") {
                    openPlayer(first)
                }
                .buttonStyle(.plain)
                .font(.system(size: metrics.subtitle, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .help("Abrir \(first.displayName)")
            }
        }
    }

    @ViewBuilder
    private func fullRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
                .onTapGesture(perform: openCurrentPlayer)
            VStack(alignment: .center, spacing: metrics.gap * 0.35) {
                combinedTitle(metrics: metrics)
                progressRow(metrics: metrics, showTimes: true)
            }
            .frame(minWidth: 16, maxWidth: .infinity, alignment: .center)
            controls(metrics: metrics, layout: .full)
        }
    }

    @ViewBuilder
    private func compactRow(metrics: LayoutMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            artworkTile(side: metrics.art)
                .onTapGesture(perform: openCurrentPlayer)
            VStack(alignment: .center, spacing: metrics.gap * 0.35) {
                combinedTitle(metrics: metrics)
                progressRow(metrics: metrics, showTimes: false)
            }
            .frame(minWidth: 16, maxWidth: .infinity, alignment: .center)
            controls(metrics: metrics, layout: .compact)
        }
    }

    @ViewBuilder
    private func minimalRow(metrics: LayoutMetrics) -> some View {
        VStack(spacing: metrics.gap * 0.5) {
            VStack(alignment: .center, spacing: 0) {
                playingTitle(metrics: metrics)
                Text(subtitleLine)
                    .font(.system(size: metrics.subtitle))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, metrics.height * 0.25)
            .frame(minWidth: 16, maxWidth: .infinity, alignment: .center)
            .clipped()
            controls(metrics: metrics, layout: .minimal)
        }
    }

    private func playingTitle(metrics: LayoutMetrics) -> some View {
        let title = center.state.track?.title ?? ""
        return ScrollingTitle(
            content: Text(title)
                .font(.system(size: metrics.title, weight: .semibold))
                .foregroundStyle(.primary),
            label: title,
            isVisible: window.isPanelVisible,
            reduceMotion: reduceMotion
        )
        .onTapGesture(perform: openCurrentPlayer)
    }

    private func combinedTitle(metrics: LayoutMetrics) -> some View {
        let title = center.state.track?.title ?? ""
        let suffix = subtitleLine.isEmpty ? "" : " · \(subtitleLine)"
        return ScrollingTitle(
            content: Text(title)
                .font(.system(size: metrics.title, weight: .semibold))
                .foregroundStyle(.primary)
                + Text(suffix)
                .font(.system(size: metrics.subtitle))
                .foregroundStyle(.secondary),
            label: title + suffix,
            isVisible: window.isPanelVisible,
            reduceMotion: reduceMotion
        )
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
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
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
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
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
                    label: "Aleatório",
                    size: metrics.button,
                    enabled: commands.contains(.shuffle),
                    emphasized: center.state.shuffle == true
                ) {
                    center.perform(.setShuffle(!(center.state.shuffle ?? false)))
                }
            }
            ControlButton(system: "backward.fill", label: "Anterior", size: metrics.button, enabled: commands.contains(.previous), compact: layout == .minimal) {
                center.perform(.previous)
            }
            playButton(metrics: metrics, enabled: commands.contains(.togglePlayPause))
            ControlButton(system: "forward.fill", label: "Próxima", size: metrics.button, enabled: commands.contains(.next), compact: layout == .minimal) {
                center.perform(.next)
            }
            if layout == .full {
                ControlButton(
                    system: center.state.repeatMode == .one ? "repeat.1" : "repeat",
                    label: "Repetir",
                    size: metrics.button,
                    enabled: commands.contains(.repeatAll) || commands.contains(.repeatOne),
                    emphasized: (center.state.repeatMode ?? .off) != .off
                ) {
                    cycleRepeat()
                }
            }
        }
        .fixedSize()
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
        .accessibilityLabel(center.state.status == .playing ? "Pausar" : "Reproduzir")
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
            Text("Reprodução no \(center.state.playerDisplayName ?? player.displayName)")
        } else {
            Text("Nenhuma reprodução detectada")
        }
        Divider()
        ForEach(center.installedPlayers, id: \.self) { id in
            Button("Abrir \(id.displayName)") { openPlayer(id) }
        }
        if !center.state.permissionIssues.isEmpty {
            Divider()
            ForEach(center.installedPlayers.filter { center.state.permissionIssues.contains(.automation($0)) }, id: \.self) { id in
                Button("Ativar controle de \(id.displayName)…") {
                    guard !requestingAutomation else { return }
                    requestingAutomation = true
                    Task {
                        defer { requestingAutomation = false }
                        do { try await center.requestAutomation(for: id) }
                        catch { showError(error) }
                    }
                }
                .disabled(requestingAutomation)
            }
            Button("Abrir Ajustes de Automação…") {
                openPrefs("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            }
        }
        Divider()
        Menu("Distância da Dock") {
            edgeGapButton("Igual à Dock", .matchDock)
            edgeGapButton("Pequena", .small)
            edgeGapButton("Média", .medium)
            edgeGapButton("Grande", .large)
        }
        Toggle("Abrir ao iniciar sessão", isOn: Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { enabled in
                do { try LaunchAtLogin.setEnabled(enabled) }
                catch { showError(error) }
                loginStatus = LaunchAtLogin.status
            }
        ))
        if loginStatus == .requiresApproval {
            Button("Aprovar início de sessão nos Ajustes…") { LaunchAtLogin.openSettings() }
        }
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
        openPlayer(id)
    }

    private func openPlayer(_ id: PlayerID) {
        Task {
            do { try await center.openPlayer(id) }
            catch { showError(error) }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Não foi possível concluir a ação"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        if !NSWorkspace.shared.open(url) {
            showError(NSError(domain: "dev.nowdock.NowDock", code: 3, userInfo: [NSLocalizedDescriptionKey: "Não foi possível abrir os Ajustes do Sistema."]))
        }
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

struct ScrollingTitle: View {
    let content: Text
    let label: String
    let isVisible: Bool
    let reduceMotion: Bool
    @State private var textWidth: CGFloat = 0
    @State private var replay = false

    var body: some View {
        content
            .lineLimit(1)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            .hidden()
            .overlay {
                GeometryReader { viewport in
                    if isVisible && !reduceMotion && textWidth > viewport.size.width {
                        content
                            .fixedSize(horizontal: true, vertical: false)
                            .keyframeAnimator(initialValue: CGFloat.zero, trigger: replay) { view, x in
                                if x == 0 {
                                    content
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .frame(width: viewport.size.width, alignment: .center)
                                } else {
                                    view.offset(x: x)
                                }
                            } keyframes: { _ in
                                MoveKeyframe(viewport.size.width)
                                LinearKeyframe(-textWidth, duration: (viewport.size.width + textWidth) / 28)
                                MoveKeyframe(0)
                                LinearKeyframe(0, duration: 0.1)
                            }
                            .onAppear { replay.toggle() }
                            .onChange(of: viewport.size.width) { replay.toggle() }
                            .onChange(of: label) { replay.toggle() }
                            .onHover { hovering in
                                if hovering { replay.toggle() }
                            }
                    } else {
                        content
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: viewport.size.width, alignment: .center)
                    }
                }
                .clipped()
            }
            .background {
                content
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        GeometryReader { natural in
                            Color.clear.onChange(of: natural.size.width, initial: true) {
                                textWidth = natural.size.width
                            }
                        }
                    }
                    .hidden()
            }
            .clipped()
            .padding(.horizontal, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .help(label)
    }
}

private struct LayoutMetrics {
    let height: CGFloat
    private let floorScale: CGFloat
    private let layout: PanelLayout

    init(width: CGFloat, height: CGFloat, layout: PanelLayout) {
        let aspectRatio: CGFloat
        switch layout {
        case .full: aspectRatio = 5
        case .compact: aspectRatio = 4
        case .minimal: aspectRatio = 2
        }
        self.height = min(layout == .minimal ? height * 0.75 : height, width / aspectRatio)
        floorScale = min(1, height / 52)
        self.layout = layout
    }
    var pad: CGFloat { max(4 * floorScale, height * 0.1) }
    var art: CGFloat { max(20 * floorScale, height - pad * 2) }
    var title: CGFloat { min(layout == .minimal ? 12 : 14, max(10 * floorScale, height * 0.28)) }
    var subtitle: CGFloat { min(layout == .minimal ? 9 : 11, max(8 * floorScale, height * 0.20)) }
    var time: CGFloat { max(7 * floorScale, height * 0.16) }
    var play: CGFloat { max(14 * floorScale, height * 0.42) }
    var playCircle: CGFloat { max(20 * floorScale, height * 0.52) }
    var button: CGFloat { max(11 * floorScale, height * 0.30) }
    var seek: CGFloat { max(3 * floorScale, height * 0.06) }
    var gap: CGFloat { max(4 * floorScale, height * 0.08) }
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
    let label: String
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
        .accessibilityLabel(label)
    }
}
