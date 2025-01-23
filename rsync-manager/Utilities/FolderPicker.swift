//
//  FolderPicker.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import SwiftUI

struct FolderPicker: View {
    let label: String
    @Binding var path: String

    var body: some View {
        HStack {
            Text("\(label):")
            Text(path.isEmpty ? "Select a folder..." : path)
                .foregroundColor(path.isEmpty ? .gray : .primary)
            Button("Browse") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK {
                    path = panel.url?.path ?? ""
                }
            }
        }
    }
}
