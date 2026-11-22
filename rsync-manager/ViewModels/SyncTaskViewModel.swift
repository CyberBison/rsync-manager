//
//  SyncTaskViewModel.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

@MainActor
class SyncTaskViewModel: ObservableObject {
    @Published var tasks: [SyncTask] = []
    @Published var selectedTask: SyncTask?
    @Published var logs: [LogEntry] = []
    
    @Published private(set) var runningTaskID: UUID?
    @Published private(set) var runStartedAt: Date?
    @Published private(set) var isStopping = false
    private var runningProcess: Process?

    private let tasksFileName = "sync_tasks.json"
    private let logsFileName = "sync_logs.json"
    
    private let storageDirectory: URL?

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
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
    
    func updateTask(_ task: SyncTask, name: String, arguments: String, source: String, destination: String) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = SyncTask(
                    id: task.id,
                    name: name,
                    arguments: arguments,
                    source: source,
                    destination: destination,
                    lastSyncDate: task.lastSyncDate,
                    lastSyncStatus: task.lastSyncStatus,
                    isActive: task.isActive
                )
            }
        }
    
    func runSync(task: SyncTask) {
        guard runningTaskID == nil else { return }
        ensureLocalPathsAccess([task.source, task.destination]) { [weak self] granted in
            guard let self, granted else { return }
            self.executeSyncProcess(task: task)
        }
    }

    private func executeSyncProcess(task: SyncTask) {
        guard runningTaskID == nil else { return }
        let startDate = Date()
        runningTaskID = task.id
        runStartedAt = startDate
        isStopping = false
        let progressSession = beginRealtimeProgress(for: task, startedAt: startDate)
        do {
            let resolvedSource = resolvedLocalPath(task.source)
            let resolvedDestination = resolvedLocalPath(task.destination)
            let prepared = try prepareSSHExecution(for: task, source: resolvedSource, destination: resolvedDestination)
            let command = progressSession?.decorateCommand(prepared.command) ?? prepared.command
            runningProcess = try ShellHelper.startCommand(
                command,
                environment: prepared.environment,
                cleanup: prepared.cleanup,
                onOutput: progressSession?.onOutput
            ) { [weak self] output, exitCode in
                guard let self else { return }
                let cancelled = self.isStopping
                let status = cancelled ? "cancelled" : (exitCode == 0 ? "success" : "error")
                let finalOutput = progressSession?.finalOutput(output) ?? output
                let result = cancelled ? "Sync cancelled by user.\n" + finalOutput : finalOutput
                let succeeded = exitCode == 0 && !cancelled
                if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[index].lastSyncDate = Date()
                    self.tasks[index].lastSyncStatus = status
                }
                if let finalizeLog = progressSession?.finalizeLog {
                    finalizeLog(result, succeeded)
                } else {
                    self.addLog(taskId: task.id, result: result, success: succeeded)
                }
                self.saveTasks()
                self.runningTaskID = nil
                self.runningProcess = nil
                self.runStartedAt = nil
                self.isStopping = false
                progressSession?.reset()
            }
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].lastSyncDate = Date()
                tasks[index].lastSyncStatus = "error"
            }
            if let finalizeLog = progressSession?.finalizeLog {
                finalizeLog(error.localizedDescription, false)
            } else {
                addLog(taskId: task.id, result: error.localizedDescription, success: false)
            }
            saveTasks()
            runningTaskID = nil
            runStartedAt = nil
            progressSession?.reset()
        }
    }

    func stopSync() {
        guard let process = runningProcess, process.isRunning else { return }
        isStopping = true
        process.terminate()
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
        storageDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var isRequestingFolderAccess = false
    lazy var folderAccessManager = FolderSandboxAccessManager(bypassPermissionPrompts: storageDirectory != nil)

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

struct RealtimeProgressSession {
    let decorateCommand: @MainActor (String) -> String
    let onOutput: @MainActor (String) -> Void
    let finalOutput: @MainActor (String) -> String
    let finalizeLog: @MainActor (String, Bool) -> Void
    let reset: @MainActor () -> Void
}

@MainActor
protocol SyncTaskExecutionHooks: AnyObject {}

extension SyncTaskExecutionHooks {
    func ensureLocalPathsAccess(_ paths: [String], completion: @escaping @MainActor (Bool) -> Void) {
        completion(true)
    }

    func resolvedLocalPath(_ path: String) -> String {
        path
    }

    func prepareSSHExecution(
        for task: SyncTask,
        source: String,
        destination: String
    ) throws -> (command: String, environment: [String: String], cleanup: (@Sendable () -> Void)?) {
        let command = "exec /usr/bin/rsync \(task.arguments) \(ShellHelper.quote(source)) \(ShellHelper.quote(destination))"
        return (command, [:], nil)
    }

    func beginRealtimeProgress(for task: SyncTask, startedAt: Date) -> RealtimeProgressSession? {
        nil
    }
}

extension SyncTaskViewModel: SyncTaskExecutionHooks {}
