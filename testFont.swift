import SwiftUI
import AppKit

@MainActor
func run() {
    let v1 = Text("Hello").font(.custom("Times", size: 12.0))
    let hc1 = NSHostingController(rootView: v1)
    hc1.view.layoutSubtreeIfNeeded()
    
    let v2 = Text("Hello").font(.custom("Times", size: 48.0))
    let hc2 = NSHostingController(rootView: v2)
    hc2.view.layoutSubtreeIfNeeded()
    
    print("Size 12: \(hc1.view.fittingSize)")
    print("Size 48: \(hc2.view.fittingSize)")
}
run()
