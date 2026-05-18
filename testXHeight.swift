import AppKit

let timesFont = NSFont(name: "Times New Roman", size: 12.0)!
let sysBody = NSFont.preferredFont(forTextStyle: .body)

print("Times New Roman 12pt xHeight:", timesFont.xHeight)
print("System body xHeight:", sysBody.xHeight)
print("Times New Roman 12pt pointSize:", timesFont.pointSize)

// What system font size gives the same xHeight as Times New Roman 12pt?
let targetXHeight = timesFont.xHeight
// body scales linearly with pointSize
let sysBodyXHeight = sysBody.xHeight
let sysBodySize = sysBody.pointSize
let scaledSize = sysBodySize * (targetXHeight / sysBodyXHeight)
print("System font size with matching xHeight:", scaledSize)

// Verify
let scaledSysFont = NSFont.systemFont(ofSize: scaledSize)
print("Scaled system font xHeight:", scaledSysFont.xHeight)
