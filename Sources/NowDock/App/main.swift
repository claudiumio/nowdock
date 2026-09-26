import AppKit

// Top-level code here runs on the main thread, so assuming MainActor is safe.
let delegate = MainActor.assumeIsolated { AppDelegate() }
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
