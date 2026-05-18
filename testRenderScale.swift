import Cocoa
import SwiftUI

@MainActor
func run() {
    let baseFontSize: CGFloat = 12.0
    let scale: CGFloat = 4.0
    let renderFontSize = baseFontSize * scale
    
    let view = Text("Hello").font(.system(size: renderFontSize))
    let hc = NSHostingController(rootView: view)
    let size = hc.view.fittingSize
    hc.view.frame = CGRect(origin: .zero, size: size)
    
    let rep = hc.view.bitmapImageRepForCachingDisplay(in: hc.view.bounds)!
    hc.view.cacheDisplay(in: hc.view.bounds, to: rep)
    
    let img = NSImage(size: CGSize(width: size.width / scale, height: size.height / scale))
    img.addRepresentation(rep)
    print("Logical image size: \(img.size), Physical pixels: \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
run()
