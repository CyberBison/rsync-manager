import AppKit
import Foundation
import SwiftUI
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

    @Test func progressTrackerUpdatesPercentageWithoutRewritingHistory() {
        var tracker = RsyncProgressTracker()
        tracker.ingest("Transfer starting: 3 files\nfile1.txt\n 32768 50% 32.00KB/s 00:00:01\r")
        #expect(tracker.currentTransferFile == "file1.txt")
        #expect(tracker.progress == 0.25)
        #expect(tracker.formattedOutput == "Transfer starting: 3 files\nfile1.txt\n")

        tracker.ingest(" 65536 100% 64.00KB/s 00:00:01 (xfer#1, to-check=1/3)\nfile2")
        #expect(tracker.currentTransferFile == "file1.txt")
        #expect(tracker.progress == 0.50)
        #expect(tracker.formattedOutput == "Transfer starting: 3 files\nfile1.txt\n")

        tracker.ingest(" to-check=1/3.txt\n\r 32.00K 50% 32.00KB/s 00:00:01\r")
        #expect(tracker.currentTransferFile == "file2 to-check=1/3.txt")
        #expect(tracker.progress == 0.75)
        #expect(tracker.formattedOutput == "Transfer starting: 3 files\nfile1.txt\nfile2 to-check=1/3.txt\n")

        tracker.ingest(" 64.00K 100% 64.00KB/s 00:00:01 (xfr#2, to-chk=0/3)\r")
        tracker.ingest("\nsent 65536 bytes\r\nrsync error: incomplete transfer")
        tracker.finish()
        #expect(tracker.progress == 1.0)
        #expect(tracker.formattedOutput == "Transfer starting: 3 files\nfile1.txt\nfile2 to-check=1/3.txt\nsent 65536 bytes\nrsync error: incomplete transfer")
    }

    @MainActor @Test func historyKeepsScrollPositionWhenOutputGrows() throws {
        let output = (1...100).map { "File \($0) " + String(repeating: "x", count: 150) + "\n" }.joined()
        let host = NSHostingView(rootView: RunOutputView(output: output))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.contentView = nil }
        window.contentView = host
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let scrollView = try #require(outputScrollView(in: host))
        let textView = try #require(scrollView.documentView as? NSTextView)
        let clipView = scrollView.contentView
        #expect(textView.frame.width > clipView.bounds.width)
        #expect(textView.frame.height > clipView.bounds.height)
        let selection = NSRange(location: 40, length: 16)
        textView.setSelectedRange(selection)
        clipView.scroll(to: CGPoint(x: 200, y: 450))
        scrollView.reflectScrolledClipView(clipView)
        let origin = clipView.bounds.origin
        #expect(origin.x > 0 && origin.y > 0)

        let updatedOutput = output + "Newly synced file\n"
        host.rootView = RunOutputView(output: updatedOutput)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(textView.string == updatedOutput)
        #expect(clipView.bounds.origin == origin)
        #expect(textView.selectedRange() == selection)
    }

    @MainActor private func outputScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap { outputScrollView(in: $0) }.first
    }

    @MainActor @Test func runningSyncUpdatesLatestActivityAndHistoryImmediately() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("source")
        let destination = directory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 65, count: 96 * 1024).write(to: source.appendingPathComponent("sample.bin"))

        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "Live", arguments: "-av --bwlimit=32", source: source.path + "/", destination: destination.path)
        let task = try #require(model.tasks.first)

        model.runSync(task: task)
        #expect(model.runningTaskID == task.id)
        #expect(model.tasks.first?.lastSyncStatus == "running")
        #expect(model.logs.last?.displayStatus == "running")
        #expect(model.syncProgress == 0.0)

        var observedLiveOutput = false
        var observedIntermediateProgress = false
        for _ in 0..<200 where model.runningTaskID != nil {
            if let log = model.logs.last, log.displayStatus == "running", !log.result.isEmpty {
                observedLiveOutput = true
            }
            if let progress = model.syncProgress, progress > 0 {
                observedIntermediateProgress = true
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(observedLiveOutput)
        #expect(observedIntermediateProgress)
        #expect(model.runningTaskID == nil)
        #expect(model.syncProgress == nil)
        #expect(model.tasks.first?.lastSyncStatus == "success")
        #expect(model.logs.last?.displayStatus == "success")
        #expect(model.logs.last?.success == true)
        #expect(model.logs.last?.result.contains("sample.bin\n") == true)
        #expect(model.logs.last?.result.contains("to-check=") == false)
    }

    @MainActor @Test func staleRunningStateResetsOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let taskID = UUID()
        let task = SyncTask(id: taskID, name: "Interrupted", arguments: "-av", source: "/a", destination: "/b", lastSyncDate: Date(), lastSyncStatus: "running", isActive: true)
        let log = LogEntry(id: UUID(), timestamp: Date(), taskId: taskID, result: "Transfer starting: 2 files", success: false, status: "running")
        try JSONEncoder().encode([task]).write(to: directory.appendingPathComponent("sync_tasks.json"))
        try JSONEncoder().encode([log]).write(to: directory.appendingPathComponent("sync_logs.json"))

        let model = SyncTaskViewModel(storageDirectory: directory)
        #expect(model.tasks.first?.lastSyncStatus == "error")
        #expect(model.logs.first?.displayStatus == "error")
        #expect(model.logs.first?.status == nil)
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
