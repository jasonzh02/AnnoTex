import Cocoa

let sysFont = NSFont.systemFont(ofSize: 12.0)
let serifFont = NSFont(descriptor: NSFontDescriptor().withDesign(.serif)!, size: 12.0)

print("System xHeight: \(sysFont.xHeight)")
print("Serif xHeight: \(serifFont?.xHeight ?? 0)")
