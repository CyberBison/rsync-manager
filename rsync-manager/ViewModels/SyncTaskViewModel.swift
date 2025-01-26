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
    @Published var logs: [LogEntry] = []
    
    private let tasksFileName = "sync_tasks.json"
    private let logsFileName = "sync_logs.json"
    
    init() {
        loadTasks()
        loadLogs()
    }
    
    func addTask(name: String, arguments: String, source: String, destination: String) {
        let newTask = SyncTask(
            id: UUID(),
            name: name,
            arguments: arguments,
            source: source,
            destination: destination,
            lastSyncDate: nil,
            lastSyncStatus: nil,
            isActive: true
        )
        tasks.append(newTask)
    }
    
    func runSync(task: SyncTask) {
        do {
            
            // Prepare the rsync command
            let command = """
            /usr/bin/rsync \(task.arguments) "\(task.source)" "\(task.destination)"
            """
            

            // Run the rsync command using ShellHelper
            let result = try ShellHelper.runCommand(command)
            print("Sync Result: \(result)")

            let isError = result.contains("rsync error")
            let syncStatus = isError ? "error" : "success"
            
            // Update the last sync date
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].lastSyncDate = Date()
                tasks[index].lastSyncStatus = syncStatus
            }
            addLog(taskId: task.id, result: result, success: true)
        } catch {
            print("Error running sync: \(error)")
            
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].lastSyncDate = Date()
                tasks[index].lastSyncStatus = "error"
            }
            
            addLog(taskId: task.id, result: "\(error)", success: false)
        }
    }
    
    func saveTasks() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(tasksFileName)
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL)
            print("Tasks saved successfully to \(fileURL)")
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }
    
    func loadTasks() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(tasksFileName)
        do {
            let data = try Data(contentsOf: fileURL)
            tasks = try JSONDecoder().decode([SyncTask].self, from: data)
            print("Tasks loaded successfully from \(fileURL)")
        } catch {
            print("No tasks to load or failed to load tasks: \(error)")
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func saveLogs() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(logsFileName)
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL)
            print("Logs saved successfully to \(fileURL)")
        } catch {
            print("Failed to save logs: \(error)")
        }
    }
    
    func loadLogs() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(logsFileName)
        do {
            let data = try Data(contentsOf: fileURL)
            logs = try JSONDecoder().decode([LogEntry].self, from: data)
            print("Logs loaded successfully from \(fileURL)")
        } catch {
            print("No logs to load or failed to load logs: \(error)")
        }
    }
    
    func addLog(taskId: UUID, result: String, success: Bool) {
        let newLog = LogEntry(id: UUID(), timestamp: Date(), taskId: taskId, result: result, success: success)
        logs.append(newLog)
        saveLogs()
    }
    
    
}
