import Cocoa
import SwiftUI

@MainActor
func test() {
    let view = Text("Hello World")
        .font(.system(size: 24))
        .padding(8)
        .background(Color.white)
        
    let hc = NSHostingController(rootView: view)
    let size = hc.view.fittingSize
    hc.view.frame = CGRect(origin: .zero, size: size)
    
    let pdfData = hc.view.dataWithPDF(inside: hc.view.bounds)
    print("PDF Data length: \(pdfData.count)")
}
test()
