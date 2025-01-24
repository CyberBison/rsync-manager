//
//  ContentView.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var path: [String] = [] // Navigation path
    @StateObject private var viewModel = SyncTaskViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            MainListView(onAddTask: { path.append("addTask") })
                .environmentObject(viewModel)
                .onChange(of: viewModel.tasks) { _ in
                    viewModel.saveTasks()
                }
                .navigationDestination(for: String.self) { destination in
                    switch destination {
                        
                    case "logs":
                        LogsView()
                            .environmentObject(viewModel)
                    case "addTask":
                        FormView(onDismiss: { path.removeLast() })
                            .environmentObject(viewModel)
                    case "settings":
                        SettingsView()
                    default:
                        EmptyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Logs") {
                            path.append("logs")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Settings") {
                            path.append("settings")
                        }
                    }
                }
        }
    }
}
