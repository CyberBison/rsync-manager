import AppKit
import SwiftUI

struct FolderPicker: View {
    let label: String
    @Binding var path: String

    var body: some View {
        LabeledContent(label) {
            HStack {
                TextField("", text: $path, prompt: Text("Choose or enter a path"))
                    .accessibilityLabel("\(label) path")
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.title = "Choose \(label.lowercased()) folder"
                    panel.prompt = "Choose"
                    panel.allowsMultipleSelection = false
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    if let window = NSApp.keyWindow {
                        panel.beginSheetModal(for: window) { response in
                            if response == .OK { path = panel.url?.path ?? "" }
                        }
                    }
                }
                .accessibilityLabel("Choose \(label.lowercased()) folder")
            }
        }
    }
}
