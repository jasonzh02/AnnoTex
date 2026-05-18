import Cocoa
import SwiftUI

@MainActor
func test() {
    let view = Text("Hello")
        .font(.system(size: 24))
        .scaleEffect(4.0, anchor: .topLeading)
    
    let hc = NSHostingController(rootView: view)
    hc.view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
    let size = hc.view.fittingSize
    print("Fitting size: \(size)")
}
test()
