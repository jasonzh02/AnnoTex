import Cocoa
import SwiftUI

@MainActor
func run() {
    let baseFontSize: CGFloat = 12.0
    let scale: CGFloat = 4.0
    let renderFontSize = baseFontSize * scale
    
    let view = Text("Hello").font(.custom("Helvetica", size: renderFontSize))
    let hc = NSHostingController(rootView: view)
    let size = hc.view.fittingSize
    print("Fitting size: \(size)")
}
run()
