import Cocoa

for name in NSFontManager.shared.availableFontFamilies {
    if name.contains("Times") {
        print(name)
    }
}
