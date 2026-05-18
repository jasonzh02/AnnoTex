import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        tf.isEditable = true
        tf.cell?.wraps = true
        tf.cell?.isScrollable = true
        window.contentView?.addSubview(tf)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tf)
        
        // Simulate typing
        tf.stringValue = "Testing crash Testing crash Testing crash Testing crash"
        print("Set string value")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
