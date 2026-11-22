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
    let passwordStore: SSHPasswordStore
    let sshAccessManager = SSHSandboxAccessManager()

    var fallbackKnownHostsURL: URL {
        getDocumentsDirectory().appendingPathComponent("known_hosts")
    }

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
        self.passwordStore = SSHPasswordStore(storageDirectory: storageDirectory)
        loadTasks()
        loadLogs()
    }
    
    func addTask(
        name: String,
        arguments: String,
        source: String,
        destination: String,
        sourceType: EndpointLocationType = .local,
        destinationType: EndpointLocationType = .local,
        sshConfiguration: SSHConfiguration? = nil,
        sshPassword: String? = nil
    ) {
        let resolvedSource = sourceType == .ssh ? (sshConfiguration?.formattedEndpoint ?? source) : source
        let resolvedDestination = destinationType == .ssh ? (sshConfiguration?.formattedEndpoint ?? destination) : destination
        let activeSSH = (sourceType == .ssh || destinationType == .ssh) ? sshConfiguration : nil
        let newTask = SyncTask(
            id: UUID(),
            name: name,
            arguments: arguments,
            source: resolvedSource,
            destination: resolvedDestination,
            lastSyncDate: nil,
            lastSyncStatus: nil,
            isActive: true,
            sourceType: sourceType,
            destinationType: destinationType,
            sshConfiguration: activeSSH
        )
        if let activeSSH, activeSSH.usesPassword, let sshPassword {
            passwordStore.setPassword(sshPassword, for: newTask.id)
        }
        tasks.append(newTask)
    }
    
    func updateTask(
        _ task: SyncTask,
        name: String,
        arguments: String,
        source: String,
        destination: String,
        sourceType: EndpointLocationType = .local,
        destinationType: EndpointLocationType = .local,
        sshConfiguration: SSHConfiguration? = nil,
        sshPassword: String? = nil
    ) {
        let resolvedSource = sourceType == .ssh ? (sshConfiguration?.formattedEndpoint ?? source) : source
        let resolvedDestination = destinationType == .ssh ? (sshConfiguration?.formattedEndpoint ?? destination) : destination
        let activeSSH = (sourceType == .ssh || destinationType == .ssh) ? sshConfiguration : nil
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = SyncTask(
                id: task.id,
                name: name,
                arguments: arguments,
                source: resolvedSource,
                destination: resolvedDestination,
                lastSyncDate: task.lastSyncDate,
                lastSyncStatus: task.lastSyncStatus,
                isActive: task.isActive,
                sourceType: sourceType,
                destinationType: destinationType,
                sshConfiguration: activeSSH
            )
        }
        if let activeSSH, activeSSH.usesPassword {
            if let sshPassword {
                passwordStore.setPassword(sshPassword, for: task.id)
            }
        } else {
            passwordStore.deletePassword(for: task.id)
        }
    }

    func deleteTask(_ task: SyncTask) {
        passwordStore.deletePassword(for: task.id)
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }

    func buildSSHCommand(for ssh: SSHConfiguration, hasSSHDirAccess: Bool = true) -> String {
        var parts = ["/usr/bin/ssh", "-o StrictHostKeyChecking=accept-new"]
        if !hasSSHDirAccess {
            parts.append("-o UserKnownHostsFile=\(ShellHelper.quote(fallbackKnownHostsURL.path))")
        }
        if let port = ssh.port, port > 0 {
            parts.append("-p \(port)")
        }
        switch ssh.authMethod {
        case .sshAgent:
            parts.append("-o BatchMode=yes")
        case .publicKey:
            let trimmedKey = ssh.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                let expandedKey = sshAccessManager.expandRealHomePath(trimmedKey)
                parts.append("-i \(ShellHelper.quote(expandedKey))")
                parts.append("-o IdentitiesOnly=yes")
            }
            parts.append("-o BatchMode=yes")
        case .password:
            parts.append("-o PreferredAuthentications=keyboard-interactive,password")
            parts.append("-o PubkeyAuthentication=no")
            parts.append("-o NumberOfPasswordPrompts=1")
        case .certificate:
            let trimmedKey = ssh.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                let expandedKey = sshAccessManager.expandRealHomePath(trimmedKey)
                parts.append("-i \(ShellHelper.quote(expandedKey))")
            }
            let trimmedCert = ssh.certificatePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCert.isEmpty {
                let expandedCert = sshAccessManager.expandRealHomePath(trimmedCert)
                parts.append("-o CertificateFile=\(ShellHelper.quote(expandedCert))")
            }
            parts.append("-o IdentitiesOnly=yes")
            parts.append("-o BatchMode=yes")
        }
        return parts.joined(separator: " ")
    }

    func buildRsyncCommand(for task: SyncTask, hasSSHDirAccess: Bool = true) -> String {
        let sourceArg = task.sourceType == .ssh
            ? (task.sshConfiguration?.formattedEndpoint ?? task.source)
            : task.source
        let destArg = task.destinationType == .ssh
            ? (task.sshConfiguration?.formattedEndpoint ?? task.destination)
            : task.destination

        var extraArgs = ""
        let tokens = task.arguments.split(whereSeparator: \.isWhitespace)
        let hasCustomRsh = tokens.contains("-e") || tokens.contains { $0.hasPrefix("--rsh") }
        if task.usesSSH, !hasCustomRsh, let ssh = task.sshConfiguration {
            let sshCmd = buildSSHCommand(for: ssh, hasSSHDirAccess: hasSSHDirAccess)
            extraArgs = " -e \(ShellHelper.quote(sshCmd))"
        }
        return "exec /usr/bin/rsync \(task.arguments)\(extraArgs) \(ShellHelper.quote(sourceArg)) \(ShellHelper.quote(destArg))"
    }
    
    func runSync(task: SyncTask) {
        guard runningTaskID == nil else { return }
        runningTaskID = task.id
        runStartedAt = Date()
        isStopping = false
        do {
            // Keep the existing shell-based free-form arguments. Quote folder paths
            // literally so spaces, apostrophes, and shell characters remain paths.
            var hasSSHDirAccess = true
            if task.usesSSH {
                hasSSHDirAccess = storageDirectory != nil ? true : sshAccessManager.activateSavedSSHDirectoryAccess()
                if let ssh = task.sshConfiguration {
                    sshAccessManager.activateBookmarkedFile(at: ssh.keyPath)
                    sshAccessManager.activateBookmarkedFile(at: ssh.certificatePath)
                    if ssh.authMethod == .sshAgent && hasSSHDirAccess {
                        sshAccessManager.activateBookmarkedConfigCredentials(
                            host: ssh.host,
                            user: ssh.user,
                            port: ssh.port
                        )
                    }
                }
            }
            let command = buildRsyncCommand(for: task, hasSSHDirAccess: hasSSHDirAccess)
            var env: [String: String] = [:]
            var cleanup: (@Sendable () -> Void)? = nil
            if task.usesSSH, let ssh = task.sshConfiguration, ssh.usesPassword,
               let password = passwordStore.password(for: task.id), !password.isEmpty {
                let scriptURL = try ShellHelper.makeSSHAskPassScript()
                env["SSH_ASKPASS"] = scriptURL.path
                env["SSH_ASKPASS_REQUIRE"] = "force"
                env["DISPLAY"] = "rsync-manager"
                env["RSYNC_SSH_PASSWORD"] = password
                cleanup = { try? FileManager.default.removeItem(at: scriptURL) }
            }
            runningProcess = try ShellHelper.startCommand(command, environment: env, cleanup: cleanup) { [weak self] output, exitCode in
                guard let self else { return }
                let cancelled = self.isStopping
                let status = cancelled ? "cancelled" : (exitCode == 0 ? "success" : "error")
                if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[index].lastSyncDate = Date()
                    self.tasks[index].lastSyncStatus = status
                }
                let result = cancelled ? "Sync cancelled by user.\n" + output : output
                self.addLog(taskId: task.id, result: result, success: exitCode == 0 && !cancelled)
                self.saveTasks()
                self.runningTaskID = nil
                self.runningProcess = nil
                self.runStartedAt = nil
                self.isStopping = false
            }
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].lastSyncDate = Date()
                tasks[index].lastSyncStatus = "error"
            }
            addLog(taskId: task.id, result: error.localizedDescription, success: false)
            saveTasks()
            runningTaskID = nil
            runStartedAt = nil
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
