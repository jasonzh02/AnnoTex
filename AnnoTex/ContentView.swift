import SwiftUI

enum AppMode {
    case view
    case addMath
}

struct ContentView: View {
    @State private var fileURL: URL?
    // We create one instance of our custom PDF viewer
    @StateObject private var pdfContainer = PDFContainer()
    
    var body: some View {
        VStack {
            HStack(spacing: 20) {
                Button("📁 Open PDF") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    if panel.runModal() == .OK {
                        fileURL = panel.url
                    }
                }
                
                Button(action: {
                    pdfContainer.appMode = pdfContainer.appMode == .view ? .addMath : .view
                }) {
                    Text("Σ Add Math Mode")
                        .foregroundColor(pdfContainer.appMode == .addMath ? .white : .primary)
                        .padding(8)
                        .background(pdfContainer.appMode == .addMath ? Color.blue : Color.clear)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button("💾 Save PDF") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.pdf]
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { @MainActor in
                            _ = await pdfContainer.view.writePortableDocument(to: url)
                        }
                    }
                }
                
                if pdfContainer.hasSelectedAnnotation && !pdfContainer.isEditingAnnotation {
                    Divider().frame(height: 20)
                    
                    HStack {
                        Text("Size: \(Int(pdfContainer.fontSize))pt")
                            .monospacedDigit()
                            .frame(width: 65, alignment: .leading)
                        Slider(value: $pdfContainer.fontSize, in: 8...72)
                            .frame(width: 120)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            PDFKitView(url: fileURL, pdfView: pdfContainer.view)
                .edgesIgnoringSafeArea(.all)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AppModeChangedToView"))) { _ in
            pdfContainer.appMode = .view
        }
    }
}

// A simple helper to keep the PDFView alive across UI updates
class PDFContainer: ObservableObject {
    let view = MathPDFView()
    @Published var appMode: AppMode = .view {
        didSet {
            view.currentAppMode = appMode
        }
    }
    
    @Published var hasSelectedAnnotation: Bool = false
    @Published var isEditingAnnotation: Bool = false
    
    @Published var fontSize: CGFloat = 12.0 {
        didSet {
            view.currentFontSize = fontSize
            view.updateActiveFontSize()
        }
    }
    
    init() {
        view.onSelectionChanged = { [weak self] annotation in
            DispatchQueue.main.async {
                self?.hasSelectedAnnotation = (annotation != nil)
                if let annot = annotation {
                    self?.fontSize = annot.fontSize
                }
            }
        }
        
        view.onEditingStateChanged = { [weak self] isEditing in
            DispatchQueue.main.async {
                self?.isEditingAnnotation = isEditing
            }
        }
    }
}

// This part is for the Xcode preview window
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
