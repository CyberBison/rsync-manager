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
                    Text("Source: \(task.source)")
                    Text("Destination: \(task.destination)")
                    if let date = task.lastSyncDate {
                        Text("Last Sync: \(date, formatter: DateFormatter.shortDateTime)")
                    } else {
                        Text("Last Sync: Never")
                    }
                    Button("Sync Now") {
                        viewModel.runSync(task: task)
                    }
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
