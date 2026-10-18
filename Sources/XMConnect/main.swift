import AppKit

// IOBluetooth delivers RFCOMM callbacks on the run loop of the thread that opened the channel,
// so everything runs on the main thread's NSApplication run loop.

let app = NSApplication.shared

// Single instance.
let bundleID = Bundle.main.bundleIdentifier ?? "app.xmconnect.mac"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
