// Stand-in menu bar app for App Store media capture: one status item with an SF Symbol and a menu.
// usage: StatusDemo <sf-symbol> <menu title>
import AppKit

let args = CommandLine.arguments
let symbol = args.count > 1 ? args[1] : "circle.fill"
let title = args.count > 2 ? args[2] : "Demo"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let button = item.button {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    image?.isTemplate = true
    button.image = image
}
let menu = NSMenu()
menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
menu.addItem(.separator())
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.menu = menu

app.run()
