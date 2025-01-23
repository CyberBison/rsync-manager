//
//  SyncTaskViewModel.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

class SyncTaskViewModel: ObservableObject {
    @Published var tasks: [SyncTask] = []
    @Published var selectedTask: SyncTask?
    
    func addTask(source: String, destination: String) {
        let newTask = SyncTask(id: UUID(), source: source, destination: destination, lastSyncDate: nil, isActive: true)
        tasks.append(newTask)
    }
    
    func runSync(task: SyncTask){
        guard let source = task.source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let destination = task.destination.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return
        }
        
        let command = "rsync -av --delete '\(source)' '\(destination)'"
        do {
            let result = try ShellHelper.runCommand(command)
            print("Sync Result: \(result)")
            
            // Update the last sync date
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].lastSyncDate = Date()
            }
        }
        catch{
            print("Error running sync: \(error)")
        }
    }
}
