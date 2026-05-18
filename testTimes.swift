import Cocoa

let sysFont = NSFont.systemFont(ofSize: 12.0)
let timesFont = NSFont(name: "Times", size: 12.0)!

print("System xHeight: \(sysFont.xHeight)")
print("Times xHeight: \(timesFont.xHeight)")
