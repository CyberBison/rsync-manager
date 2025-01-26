//
//  LogsView.swift
//  rsync-manager
//
//  Created by CyberBison on 24.01.2025.
//

import SwiftUI

struct LogsView: View {
    @EnvironmentObject var viewModel: SyncTaskViewModel
    @State private var selectedTaskId: UUID? = nil // To hold the selected task ID for filtering
    
    var filteredLogs: [LogEntry] {
        if let taskId = selectedTaskId {
            return viewModel.logs.filter { $0.taskId == taskId }
        } else {
            return viewModel.logs
        }
    }
    
    var body: some View {
        VStack {
            // Filter Picker
            Picker("Filter logs", selection: $selectedTaskId) {
                Text("All Tasks").tag(UUID?.none) // Default option to show all logs
                ForEach(viewModel.tasks, id: \.id) { task in
                    Text(task.name).tag(task.id as UUID?)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            
            // Filtered Logs List
            List(filteredLogs) { log in
                VStack(alignment: .leading) {
                    if let task = viewModel.tasks.first(where: { $0.id == log.taskId }) {
                        Text("Task Name: \(task.name)")
                            .font(.headline)
                    }
                    Text("Date: \(log.timestamp, formatter: DateFormatter.shortDateTime)")
                    Text("Result: \(log.result)")
                        .foregroundColor(log.success ? .green : .red)
                }
            }
            .navigationTitle("Sync Logs")
        }
    }
}
