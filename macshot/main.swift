// Derived from MacShot v4.3.0 (sw33tLie), GPL-3.0.
// Modified 2026-10-07: standalone screenshot-only lifecycle.
import Cocoa
UserDefaults.standard.set(false, forKey: "NSViewUsesAutomaticLayerBackingStores")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
