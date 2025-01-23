//
//  FormView.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import SwiftUI

struct FormView: View {
    @EnvironmentObject var viewModel: SyncTaskViewModel
    let onDismiss: () -> Void
    @State private var source: String = ""
    @State private var destination: String = ""

    var body: some View {
        VStack {
            FolderPicker(label: "Source", path: $source)
            FolderPicker(label: "Destination", path: $destination)
            HStack {
                Button("Save") {
                    viewModel.addTask(source: source, destination: destination)
                    onDismiss()
                }
                Button("Cancel", action: onDismiss)
            }
        }
        .padding()
        .navigationTitle("Add Task")
    }
}
