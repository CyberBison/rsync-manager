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
}
