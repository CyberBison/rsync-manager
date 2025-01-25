//
//  MainListView.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import SwiftUI

struct MainListView: View {
    @EnvironmentObject var viewModel: SyncTaskViewModel
    let onAddTask: () -> Void

    var body: some View {
        VStack {
            List(viewModel.tasks) { task in
                VStack(alignment: .leading) {
                    
                    Text(task.name).font(.title).bold()
                    
                    HStack{
                        Text("Source:").bold()
                        Text(task.source)
                    }
                    HStack{
                        Text("Destination:").bold()
                        Text(task.destination)
                    }
                    if let date = task.lastSyncDate {
                        Text("Last Sync: \(date, formatter: DateFormatter.shortDateTime)")
                    } else {
                        Text("Last Sync: Never")
                    }
                    if let status = task.lastSyncStatus {
                        Label("Status: \(status)", systemImage: "circlebadge.fill")
                            .foregroundColor(status == "success" ? .green : .red)
                    }
                    Button("Sync Now") {
                        viewModel.runSync(task: task)
                    }
                    Divider()
                }
            }
            Button("Add Task", action: onAddTask)
                .padding()
        }
        .navigationTitle("Task List")
    }
}

extension DateFormatter {
    static var shortDateTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}
