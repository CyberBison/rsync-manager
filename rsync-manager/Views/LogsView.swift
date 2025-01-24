//
//  LogsView.swift
//  rsync-manager
//
//  Created by CyberBison on 24.01.2025.
//

import SwiftUI

struct LogsView: View {
    @EnvironmentObject var viewModel: SyncTaskViewModel
    
    var body: some View{
        List(viewModel.logs) { log in
            VStack(alignment: .leading) {
                Text("Task ID: \(log.taskId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Date: \(log.timestamp, formatter: DateFormatter.shortDateTime)")
                Text("Result: \(log.result)")
                    .foregroundColor(log.success ? .green : .red)
            }
        }
        .navigationTitle("Sync Logs")
    }
}
