import Cocoa

@MainActor
func run() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
    window.close()
    print("Window closed")
}
run()
