import Foundation
import Testing
@testable import rsync_manager

struct rsync_managerTests {
    @Test func legacyProfileStillLoads() throws {
        let data = Data("""
        {"id":"AA747039-EA72-4BDA-BA78-5D4D50604121","name":"Backup","source":"/a","destination":"/b","isActive":true}
        """.utf8)
        let profile = try JSONDecoder().decode(SyncTask.self, from: data)
        #expect(profile.arguments == "-av --delete")
        #expect(profile.direction == .oneWay)
        #expect(try JSONDecoder().decode(SyncTask.self, from: JSONEncoder().encode(profile)) == profile)
    }

    @Test func shellPathsRemainLiteral() throws {
        let path = "/tmp/it's a folder/$(echo should-not-expand);name"
        let output = try ShellHelper.runCommand("printf %s \(ShellHelper.quote(path))")
        #expect(output == path)
    }

    @Test func legacyErrorLogsArePresentedAsFailures() {
        let log = LogEntry(id: UUID(), timestamp: Date(), taskId: UUID(), result: "rsync error: permission denied", success: true)
        #expect(log.displayStatus == "error")
    }

    @MainActor @Test func asyncCommandReportsExitStatus() async throws {
        let result: (String, Int32) = try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try ShellHelper.startCommand("printf 'failure output'; exit 23") { output, status in
                    continuation.resume(returning: (output, status))
                }
            } catch { continuation.resume(throwing: error) }
        }
        #expect(result.0 == "failure output")
        #expect(result.1 == 23)
    }

    @MainActor @Test func stopTerminatesRunningProcess() async throws {
        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            do {
                let process = try ShellHelper.startCommand("exec /bin/sleep 30") { _, code in
                    continuation.resume(returning: code)
                }
                process.terminate()
            } catch { continuation.resume(throwing: error) }
        }
        #expect(code != 0)
    }

    @MainActor @Test func syncCopiesFilesAndRecordsFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("source with ' quote")
        let destination = directory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("A safe test file".utf8).write(to: source.appendingPathComponent("sample.txt"))
        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "Integration", arguments: "-av", source: source.path + "/", destination: destination.path)
        model.runSync(task: try #require(model.tasks.first))
        for _ in 0..<100 where model.runningTaskID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.runningTaskID == nil)
        #expect(model.logs.last?.success == true)
        #expect(try String(contentsOf: destination.appendingPathComponent("sample.txt"), encoding: .utf8) == "A safe test file")
        var missingSource = try #require(model.tasks.first)
        missingSource.source = directory.appendingPathComponent("missing").path
        model.runSync(task: missingSource)
        for _ in 0..<100 where model.runningTaskID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.logs.last?.success == false)
        #expect(model.tasks.first?.lastSyncStatus == "error")
    }

    @MainActor @Test func profilesPersistWithoutChangingTheirSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "Photos", arguments: "-av --exclude='*.tmp'", source: "/source/", destination: "/destination")
        model.saveTasks()
        let restored = SyncTaskViewModel(storageDirectory: directory)
        #expect(restored.tasks == model.tasks)
        let original = try #require(restored.tasks.first)
        restored.updateTask(original, name: "Renamed", arguments: "--dry-run", source: "/new/", destination: "/backup")
        #expect(restored.tasks.first?.id == original.id)
        #expect(restored.tasks.first?.arguments == "--dry-run")
    }

    @MainActor @Test func biSyncSanitizesArgumentsAndNormalizesPathsOnUpdate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sanitizedDelete = SyncTaskViewModel.sanitizeBiSyncArguments("-av --delete --exclude='*.tmp'")
        #expect(sanitizedDelete.sanitized == "-avu --exclude='*.tmp'")
        #expect(sanitizedDelete.strippedDelete == true)

        let sanitizedNoDelete = SyncTaskViewModel.sanitizeBiSyncArguments("-av")
        #expect(sanitizedNoDelete.sanitized == "-avu")
        #expect(sanitizedNoDelete.strippedDelete == false)

        #expect(SyncTaskViewModel.normalizedBiSyncPath("/tmp/folder") == "/tmp/folder/")
        #expect(SyncTaskViewModel.normalizedBiSyncPath("/tmp/folder///") == "/tmp/folder/")

        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "SwitchToBiSync", arguments: "-av --delete", source: "/tmp/src", destination: "/tmp/dst", direction: .oneWay)
        let original = try #require(model.tasks.first)
        model.updateTask(original, name: "SwitchToBiSync", arguments: "-av --delete", source: "/tmp/src", destination: "/tmp/dst", direction: .biSync)

        let updated = try #require(model.tasks.first)
        #expect(updated.direction == .biSync)
        #expect(updated.source == "/tmp/src/")
        #expect(updated.destination == "/tmp/dst/")
        #expect(updated.arguments == "-avu")
    }

    @MainActor @Test func biSyncMergesNewerFilesAndPropagatesDeletions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("source")
        let destination = directory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fromSource = source.appendingPathComponent("fromSource.txt")
        let fromDest = destination.appendingPathComponent("fromDest.txt")
        let sharedSource = source.appendingPathComponent("shared.txt")
        let sharedDest = destination.appendingPathComponent("shared.txt")

        try Data("from source".utf8).write(to: fromSource)
        try Data("from dest".utf8).write(to: fromDest)
        try Data("older".utf8).write(to: sharedSource)
        try Data("newer".utf8).write(to: sharedDest)

        let olderDate = Date(timeIntervalSinceNow: -60)
        let newerDate = Date()
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: sharedSource.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: sharedDest.path)

        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "BiSyncIntegration", arguments: "-av --delete", source: source.path, destination: destination.path, direction: .biSync)

        let task = try #require(model.tasks.first)
        #expect(task.source == source.path + "/")
        #expect(task.destination == destination.path + "/")

        // Run 1: Initial baseline resync merges both folders without deletions or nesting
        model.runSync(task: task)
        for _ in 0..<100 where model.runningTaskID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.runningTaskID == nil)
        #expect(model.logs.last?.success == true)
        #expect(try String(contentsOf: destination.appendingPathComponent("fromSource.txt"), encoding: .utf8) == "from source")
        #expect(try String(contentsOf: source.appendingPathComponent("fromDest.txt"), encoding: .utf8) == "from dest")
        #expect(try String(contentsOf: sharedSource, encoding: .utf8) == "newer")
        #expect(try String(contentsOf: sharedDest, encoding: .utf8) == "newer")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source").path))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("destination").path))

        // Run 2: Delete one tracked file from each side and add a new file on destination
        try FileManager.default.removeItem(at: fromSource)
        try FileManager.default.removeItem(at: fromDest)
        try Data("brand new".utf8).write(to: destination.appendingPathComponent("brandNew.txt"))

        model.runSync(task: try #require(model.tasks.first))
        for _ in 0..<100 where model.runningTaskID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.runningTaskID == nil)
        #expect(model.logs.last?.success == true)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("fromSource.txt").path))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("fromDest.txt").path))
        #expect(try String(contentsOf: source.appendingPathComponent("brandNew.txt"), encoding: .utf8) == "brand new")
        #expect(FileManager.default.fileExists(atPath: sharedSource.path))
        #expect(FileManager.default.fileExists(atPath: sharedDest.path))
    }
}
