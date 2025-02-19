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
    var task: SyncTask?
    
    @State private var name: String = ""
    @State private var arguments: String = "-av --delete"
    @State private var source: String = ""
    @State private var destination: String = ""
    
    init(task: SyncTask? = nil, onDismiss: @escaping () -> Void){
        self.task = task
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading) {
            Label("Task name:", systemImage: "bolt.horizontal")
                .bold()
            TextField("Task Name", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.bottom)
            Label("Command arguments:", systemImage: "text.and.command.macwindow")
                .bold()
            TextField("Command arguments", text: $arguments)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.bottom)
            Section {
                Link("Click here for a complete guide of rsync and a full list of arguments", destination: URL(string: "https://github.com/cyberbison/rsync-manager/blob/main/rsync_help_guide.md")!)
                    .foregroundColor(.blue)
            }
            FolderPicker(label: "Source", path: $source).bold().padding(.vertical, 5)
            FolderPicker(label: "Destination", path: $destination).bold()
            HStack {
                Button(task == nil ? "Save" : "Update") {
                    if let task = task {
                        viewModel.updateTask(task, name: name, arguments: arguments, source: source, destination: destination)
                    }
                    else {
                        viewModel.addTask(name: name, arguments: arguments, source: source, destination: destination)
                    }
                    onDismiss()
                }
                Button("Cancel", action: onDismiss)
            }
        }
        .padding()
        .navigationTitle(task == nil ? "Add Task" : "Edit Task")
        .onAppear {
                    if let task = task {
                        name = task.name
                        arguments = task.arguments
                        source = task.source
                        destination = task.destination
                    }
                }
        .onChange(of: task) {
            if let task = task {
                name = task.name
                arguments = task.arguments
                source = task.source
                destination = task.destination
            }
        }
    }
}
