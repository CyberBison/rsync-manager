import AppKit
import SwiftUI

struct FolderPicker: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
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
                    panel.canCreateDirectories = true
                    if FolderSandboxAccessManager.isLocalPath(path) {
                        let normalized = viewModel.folderAccessManager.normalizePath(path)
                        if !normalized.isEmpty {
                            panel.directoryURL = URL(fileURLWithPath: normalized, isDirectory: true)
                        }
                    }
                    let handleSelection: @MainActor (NSApplication.ModalResponse, URL?) -> Void = { response, url in
                        if response == .OK, let url {
                            viewModel.folderAccessManager.bookmarkDirectory(url)
                            path = url.path
                        }
                    }
                    if let window = NSApp.keyWindow {
                        panel.beginSheetModal(for: window) { response in
                            let selectedURL = panel.url
                            Task { @MainActor in
                                handleSelection(response, selectedURL)
                            }
                        }
                    } else {
                        let response = panel.runModal()
                        handleSelection(response, panel.url)
                    }
                }
                .accessibilityLabel("Choose \(label.lowercased()) folder")
            }
        }
    }
}
