import AppKit

Migration.runIfNeeded()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
