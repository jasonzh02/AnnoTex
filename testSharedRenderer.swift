import Cocoa
import SwiftUI

class Renderer {
    static let shared = Renderer()
    let offscreenWindow: NSWindow
    let hc: NSHostingController<AnyView>
    
    init() {
        offscreenWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 2000, height: 2000),
                                        styleMask: .borderless, backing: .buffered, defer: false)
        hc = NSHostingController(rootView: AnyView(EmptyView()))
        offscreenWindow.contentView = hc.view
    }
    
    @MainActor
    func render() {
        let view = Text("Hello").font(.system(size: 24))
        hc.rootView = AnyView(view)
        hc.view.layoutSubtreeIfNeeded()
        let size = hc.view.fittingSize
        print("Shared fitting size: \(size)")
    }
}

@MainActor
func run() {
    Renderer.shared.render()
}
run()
