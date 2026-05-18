import SwiftUI
import LaTeXSwiftUI
import AppKit

@MainActor
func test() {
    let view = LaTeX("Testing $x^2$")
    let renderer = ImageRenderer(content: view)
    if let image = renderer.nsImage {
        print("Success! Size: \(image.size)")
    } else {
        print("Failed")
    }
}
test()
