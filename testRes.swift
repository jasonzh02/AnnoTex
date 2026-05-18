import Cocoa
import SwiftUI

@MainActor
func test() {
    let view = Text("Hello").font(.system(size: 24))
    let hc = NSHostingController(rootView: view)
    hc.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 400,
        pixelsHigh: 400,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = CGSize(width: 100, height: 100)
    
    // Setting current context doesn't always affect cacheDisplay.
    // To properly scale, we can draw the view into an image:
    let img = NSImage(size: rep.size)
    img.lockFocusFlipped(true)
    if let ctx = NSGraphicsContext.current?.cgContext {
        // Just cache display
        hc.view.cacheDisplay(in: hc.view.bounds, to: rep)
    }
    img.unlockFocus()
    print("Rep size: \(rep.size), pixels: \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
test()
