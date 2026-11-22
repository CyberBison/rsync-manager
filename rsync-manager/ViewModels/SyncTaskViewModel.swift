//
//  SyncTaskViewModel.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

struct BiSyncState: Codable, Equatable {
    var sourcePath: String
    var destinationPath: String
    var trackedPaths: Set<String>
}

@MainActor
class SyncTaskViewModel: ObservableObject {
    @Published var tasks: [SyncTask] = []
    @Published var selectedTask: SyncTask?
    @Published var logs: [LogEntry] = []
    
    @Published private(set) var runningTaskID: UUID?
    @Published private(set) var runStartedAt: Date?
    @Published private(set) var isStopping = false
    private var runningProcess: Process?
    private var biSyncStates: [UUID: BiSyncState] = [:]

    private let tasksFileName = "sync_tasks.json"
    private let logsFileName = "sync_logs.json"
    private let biSyncStateFileName = "bisync_state.json"
    
    private let storageDirectory: URL?

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
        loadTasks()
        loadLogs()
        loadBiSyncStates()
    }

    static func normalizedBiSyncPath(_ path: String) -> String {
        if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }
        if path == "/" {
            return "/"
        }
        return path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/"
    }

    static func containsDeleteFlag(_ arguments: String) -> Bool {
        arguments.split(whereSeparator: { $0.isWhitespace }).contains { token in
            token == "--delete" || token.hasPrefix("--delete-")
        }
    }

    static func isDryRun(_ arguments: String) -> Bool {
        arguments.split(whereSeparator: { $0.isWhitespace }).contains { token in
            if token == "--dry-run" { return true }
            return isSimpleShortFlags(token) && token.dropFirst().contains("n")
        }
    }

    static func sanitizeBiSyncArguments(_ arguments: String) -> (sanitized: String, strippedDelete: Bool) {
        let rawTokens = arguments.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var strippedDelete = false
        var tokens: [String] = []
        for token in rawTokens {
            if token == "--delete" || token.hasPrefix("--delete-") {
                strippedDelete = true
            } else {
                tokens.append(token)
            }
        }

        let hasUpdate = tokens.contains { token in
            token == "--update" || token == "-u" || (isSimpleShortFlags(token) && token.dropFirst().contains("u"))
        }

        if !hasUpdate {
            if let shortIndex = tokens.firstIndex(where: { isSimpleShortFlags($0) }) {
                tokens[shortIndex] += "u"
            } else if tokens.isEmpty {
                tokens = ["-avu"]
            } else {
                tokens.insert("-u", at: 0)
            }
        }

        return (tokens.joined(separator: " "), strippedDelete)
    }

    private static func isSimpleShortFlags<S: StringProtocol>(_ token: S) -> Bool {
        guard token.hasPrefix("-"), !token.hasPrefix("--"), !token.contains("=") else { return false }
        let flags = token.dropFirst()
        return !flags.isEmpty && flags.allSatisfy(\.isLetter) && !flags.contains(where: { "efTMB".contains($0) })
    }
    
    func addTask(name: String, arguments: String, source: String, destination: String, direction: SyncDirection = .oneWay) {
        let resolvedSource = direction == .biSync ? Self.normalizedBiSyncPath(source) : source
        let resolvedDestination = direction == .biSync ? Self.normalizedBiSyncPath(destination) : destination
        let resolvedArguments = direction == .biSync ? Self.sanitizeBiSyncArguments(arguments).sanitized : arguments
        let newTask = SyncTask(
            id: UUID(),
            name: name,
            arguments: resolvedArguments,
            source: resolvedSource,
            destination: resolvedDestination,
            lastSyncDate: nil,
            lastSyncStatus: nil,
            isActive: true,
            direction: direction
        )
        tasks.append(newTask)
    }
    
    func updateTask(_ task: SyncTask, name: String, arguments: String, source: String, destination: String, direction: SyncDirection = .oneWay) {
        let resolvedSource = direction == .biSync ? Self.normalizedBiSyncPath(source) : source
        let resolvedDestination = direction == .biSync ? Self.normalizedBiSyncPath(destination) : destination
        let resolvedArguments = direction == .biSync ? Self.sanitizeBiSyncArguments(arguments).sanitized : arguments
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let updated = SyncTask(
                id: task.id,
                name: name,
                arguments: resolvedArguments,
                source: resolvedSource,
                destination: resolvedDestination,
                lastSyncDate: task.lastSyncDate,
                lastSyncStatus: task.lastSyncStatus,
                isActive: task.isActive,
                direction: direction
            )
            tasks[index] = updated
            if selectedTask?.id == task.id {
                selectedTask = updated
            }
        }
        if direction == .oneWay {
            if biSyncStates.removeValue(forKey: task.id) != nil {
                saveBiSyncStates()
            }
        } else if let existing = biSyncStates[task.id],
                  existing.sourcePath != resolvedSource || existing.destinationPath != resolvedDestination {
            biSyncStates.removeValue(forKey: task.id)
            saveBiSyncStates()
        }
    }
    
    func runSync(task: SyncTask) {
        guard runningTaskID == nil else { return }
        runningTaskID = task.id
        runStartedAt = Date()
        isStopping = false

        if task.direction == .biSync {
            runBiSync(task: task)
            return
        }

        do {
            // Keep the existing shell-based free-form arguments. Quote folder paths
            // literally so spaces, apostrophes, and shell characters remain paths.
            let command = "exec /usr/bin/rsync \(task.arguments) \(ShellHelper.quote(task.source)) \(ShellHelper.quote(task.destination))"
            runningProcess = try ShellHelper.startCommand(command) { [weak self] output, exitCode in
                self?.finishRun(taskId: task.id, output: output, exitCode: exitCode)
            }
        } catch {
            failRun(taskId: task.id, message: error.localizedDescription)
        }
    }

    private func runBiSync(task: SyncTask) {
        let normalizedSource = Self.normalizedBiSyncPath(task.source)
        let normalizedDestination = Self.normalizedBiSyncPath(task.destination)
        let (biSyncArgs, strippedDelete) = Self.sanitizeBiSyncArguments(task.arguments)
        let dryRun = Self.isDryRun(biSyncArgs)
        let isLocalPair = !normalizedSource.contains(":") && !normalizedDestination.contains(":")

        var prePassNotes: [String] = []
        if strippedDelete {
            prePassNotes.append("Note: Removed --delete flag for Bi-Sync safety.")
        }

        if isLocalPair {
            var srcIsDir: ObjCBool = false
            let sourceExists = FileManager.default.fileExists(atPath: normalizedSource, isDirectory: &srcIsDir) && srcIsDir.boolValue
            var dstIsDir: ObjCBool = false
            let destExists = FileManager.default.fileExists(atPath: normalizedDestination, isDirectory: &dstIsDir) && dstIsDir.boolValue

            if let prior = biSyncStates[task.id],
               prior.sourcePath == normalizedSource,
               prior.destinationPath == normalizedDestination {
                if !sourceExists || !destExists {
                    let missing = !sourceExists ? normalizedSource : normalizedDestination
                    failRun(taskId: task.id, message: "Bi-Sync aborted: folder is unavailable (\(missing)).")
                    return
                }
                let deletionNotes = Self.propagateBiSyncDeletions(
                    prior: prior,
                    sourcePath: normalizedSource,
                    destinationPath: normalizedDestination,
                    dryRun: dryRun
                )
                prePassNotes.append(contentsOf: deletionNotes)
            } else {
                prePassNotes.append("Initial Bi-Sync baseline (resync): merging both folders without deletions.")
            }
        } else {
            prePassNotes.append("Note: Stateful deletion tracking is only available for local folders.")
        }

        let quotedSource = ShellHelper.quote(normalizedSource)
        let quotedDest = ShellHelper.quote(normalizedDestination)
        let pass1Command = "exec /usr/bin/rsync \(biSyncArgs) \(quotedSource) \(quotedDest)"
        let pass2Command = "exec /usr/bin/rsync \(biSyncArgs) \(quotedDest) \(quotedSource)"

        do {
            runningProcess = try ShellHelper.startCommand(pass1Command) { [weak self] pass1Output, pass1ExitCode in
                guard let self else { return }
                let pass1Section = "=== Pass 1: Source → Destination ===\n\(pass1Output)"

                if self.isStopping || pass1ExitCode != 0 {
                    let combined = Self.combineBiSyncLog(prePassNotes: prePassNotes, sections: [pass1Section])
                    self.finishRun(taskId: task.id, output: combined, exitCode: pass1ExitCode)
                    return
                }

                do {
                    self.runningProcess = try ShellHelper.startCommand(pass2Command) { [weak self] pass2Output, pass2ExitCode in
                        guard let self else { return }
                        let pass2Section = "=== Pass 2: Destination → Source ===\n\(pass2Output)"
                        let combined = Self.combineBiSyncLog(prePassNotes: prePassNotes, sections: [pass1Section, pass2Section])

                        if !self.isStopping && pass2ExitCode == 0 && !dryRun && isLocalPair {
                            let postSource = Self.enumerateRelativePaths(at: normalizedSource)
                            let postDest = Self.enumerateRelativePaths(at: normalizedDestination)
                            self.biSyncStates[task.id] = BiSyncState(
                                sourcePath: normalizedSource,
                                destinationPath: normalizedDestination,
                                trackedPaths: postSource.intersection(postDest)
                            )
                            self.saveBiSyncStates()
                        }

                        self.finishRun(taskId: task.id, output: combined, exitCode: pass2ExitCode)
                    }
                } catch {
                    let combined = Self.combineBiSyncLog(prePassNotes: prePassNotes, sections: [pass1Section, error.localizedDescription])
                    self.failRun(taskId: task.id, message: combined)
                }
            }
        } catch {
            let combined = Self.combineBiSyncLog(prePassNotes: prePassNotes, sections: [error.localizedDescription])
            failRun(taskId: task.id, message: combined)
        }
    }

    private func finishRun(taskId: UUID, output: String, exitCode: Int32) {
        let cancelled = isStopping
        let status = cancelled ? "cancelled" : (exitCode == 0 ? "success" : "error")
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].lastSyncDate = Date()
            tasks[index].lastSyncStatus = status
            if selectedTask?.id == taskId {
                selectedTask = tasks[index]
            }
        }
        let result = cancelled ? "Sync cancelled by user.\n" + output : output
        addLog(taskId: taskId, result: result, success: exitCode == 0 && !cancelled)
        saveTasks()
        runningTaskID = nil
        runningProcess = nil
        runStartedAt = nil
        isStopping = false
    }

    private func failRun(taskId: UUID, message: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].lastSyncDate = Date()
            tasks[index].lastSyncStatus = "error"
            if selectedTask?.id == taskId {
                selectedTask = tasks[index]
            }
        }
        addLog(taskId: taskId, result: message, success: false)
        saveTasks()
        runningTaskID = nil
        runningProcess = nil
        runStartedAt = nil
        isStopping = false
    }

    private static func combineBiSyncLog(prePassNotes: [String], sections: [String]) -> String {
        var all: [String] = []
        if !prePassNotes.isEmpty {
            all.append(prePassNotes.joined(separator: "\n"))
        }
        all.append(contentsOf: sections.filter { !$0.isEmpty })
        return all.joined(separator: "\n\n")
    }

    private static func enumerateRelativePaths(at rootPath: String) -> Set<String> {
        let rootURL = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(atPath: rootURL.path) else {
            return []
        }
        var paths: Set<String> = []
        while let relativePath = enumerator.nextObject() as? String {
            paths.insert(relativePath)
        }
        return paths
    }

    private static func propagateBiSyncDeletions(
        prior: BiSyncState,
        sourcePath: String,
        destinationPath: String,
        dryRun: Bool
    ) -> [String] {
        let sourceURL = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().standardizedFileURL
        let destURL = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath().standardizedFileURL
        let sourceAll = enumerateRelativePaths(at: sourceURL.path)
        let destAll = enumerateRelativePaths(at: destURL.path)
        var notes: [String] = []

        let sortedTracked = prior.trackedPaths.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0 < $1
        }

        for relPath in sortedTracked {
            if !sourceAll.contains(relPath) && destAll.contains(relPath) {
                let targetURL = destURL.appendingPathComponent(relPath)
                if dryRun {
                    notes.append("[Dry Run] Would delete from destination: \(relPath)")
                } else if removeSyncedItem(at: targetURL) {
                    notes.append("Propagated deletion to destination: \(relPath)")
                }
            } else if !destAll.contains(relPath) && sourceAll.contains(relPath) {
                let targetURL = sourceURL.appendingPathComponent(relPath)
                if dryRun {
                    notes.append("[Dry Run] Would delete from source: \(relPath)")
                } else if removeSyncedItem(at: targetURL) {
                    notes.append("Propagated deletion to source: \(relPath)")
                }
            }
        }

        return notes
    }

    private static func removeSyncedItem(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileType = attrs[.type] as? FileAttributeType else {
            return false
        }
        if fileType == .typeDirectory {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            guard contents.isEmpty else { return false }
        }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
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

    private func saveBiSyncStates() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(biSyncStateFileName)
        do {
            let stringKeyed = Dictionary(uniqueKeysWithValues: biSyncStates.map { ($0.key.uuidString, $0.value) })
            let data = try JSONEncoder().encode(stringKeyed)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save bi-sync states: \(error)")
        }
    }

    private func loadBiSyncStates() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(biSyncStateFileName)
        do {
            let data = try Data(contentsOf: fileURL)
            let stringKeyed = try JSONDecoder().decode([String: BiSyncState].self, from: data)
            biSyncStates = Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        } catch {
            print("No bi-sync states to load or failed to load bi-sync states: \(error)")
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
