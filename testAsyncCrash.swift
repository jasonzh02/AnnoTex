import Cocoa
import SwiftUI

@MainActor
class Renderer {
    var activeWindows: [NSWindow] = []
    
    func render() {
        let view = Text("Math").font(.system(size: 24))
        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = hc.view
        hc.view.layoutSubtreeIfNeeded()
        
        // Capture immediately
        let rep = hc.view.bitmapImageRepForCachingDisplay(in: hc.view.bounds)!
        hc.view.cacheDisplay(in: hc.view.bounds, to: rep)
        
        // Keep alive for 1 second to let async MathJax finish
        activeWindows.append(win)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.activeWindows.removeAll(where: { $0 === win })
            win.close()
        }
    }
}

@MainActor
func run() {
    let r = Renderer()
    for _ in 0..<10 {
        r.render()
    }
    print("Done rendering")
    RunLoop.main.run(until: Date().addingTimeInterval(2.0))
}
run()
