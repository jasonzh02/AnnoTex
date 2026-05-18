import Cocoa
import SwiftUI

@MainActor
func run() {
    let view = Text("Hello").font(.system(size: 24))
    let hc = NSHostingController(rootView: view)
    let size = hc.view.fittingSize
    hc.view.frame = CGRect(origin: .zero, size: size)
    hc.view.wantsLayer = true
    hc.view.layer?.contentsScale = 4.0
    
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width * 4),
                               pixelsHigh: Int(size.height * 4),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    hc.view.cacheDisplay(in: hc.view.bounds, to: rep)
    NSGraphicsContext.restoreGraphicsState()
    print("Rep pixels: \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
run()
