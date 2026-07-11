import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// App de barre de menus, sans icône dans le Dock.
app.setActivationPolicy(.accessory)
app.run()
