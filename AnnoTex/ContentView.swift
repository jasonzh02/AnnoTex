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
                    Text("Σ Add Annotation")
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
                        ToolbarTextColorButton(color: pdfContainer.renderedTextColor) {
                            pdfContainer.showTextColorPanel()
                        }
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

struct ToolbarTextColorButton: View {
    let color: NSColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: color))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.plain)
        .help("Rendered text color")
    }
}

// A simple helper to keep the PDFView alive across UI updates
class PDFContainer: ObservableObject {
    let view = MathPDFView()
    private var isApplyingViewSelection = false

    @Published var appMode: AppMode = .view {
        didSet {
            view.currentAppMode = appMode
        }
    }
    
    @Published var hasSelectedAnnotation: Bool = false
    @Published var isEditingAnnotation: Bool = false
    
    @Published var fontSize: CGFloat = 12.0 {
        didSet {
            guard !isApplyingViewSelection else { return }
            view.currentFontSize = fontSize
            view.updateActiveFontSize()
        }
    }

    @Published var renderedTextColor: NSColor = .black

    func showTextColorPanel() {
        view.showTextColorPanelForActiveAnnotation()
    }
    
    init() {
        view.onSelectionChanged = { [weak self] annotation in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isApplyingViewSelection = true
                self.hasSelectedAnnotation = (annotation != nil)
                if let annot = annotation {
                    self.fontSize = annot.fontSize
                    self.renderedTextColor = annot.textColor
                }
                self.isApplyingViewSelection = false
            }
        }

        view.onActiveTextColorChanged = { [weak self] color in
            DispatchQueue.main.async {
                self?.renderedTextColor = color
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
