import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        tf.isEditable = true
        tf.usesSingleLineMode = false
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        window.contentView?.addSubview(tf)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tf)
        
        tf.stringValue = "Testing crash Testing crash Testing crash Testing crash"
        print("Success")
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
