import Cocoa

@MainActor
func run() {
    print("Testing NSTextField...")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    tf.cell?.wraps = true
    tf.cell?.isScrollable = true
    print("Success")
}
run()
