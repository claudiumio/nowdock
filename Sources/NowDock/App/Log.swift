import os

extension Logger {
    private static let subsystem = "dev.nowdock.NowDock"
    static let nowDockWindow = Logger(subsystem: subsystem, category: "window")
    static let nowDockPlaying = Logger(subsystem: subsystem, category: "nowplaying")
}
