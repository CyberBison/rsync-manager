//
//  RsyncProgressTracker.swift
//  rsync-manager
//
//  Created by CyberBison on 22.11.2026.
//

import Foundation

struct RsyncProgressTracker {
    private(set) var progress: Double?
    private(set) var currentTransferFile: String?
    private(set) var formattedOutput = ""
    private var totalEntries: Int?
    private var completedEntries = 0

    private var currentSegment = ""
    private var pendingCarriageReturn = false

    mutating func ingest(_ chunk: String) {
        for scalar in chunk.unicodeScalars {
            switch scalar {
            case "\r":
                if !pendingCarriageReturn {
                    updateTransferProgress(from: currentSegment)
                }
                pendingCarriageReturn = true
            case "\n":
                appendOutputLine(ending: "\n")
                currentSegment = ""
                pendingCarriageReturn = false
            default:
                if pendingCarriageReturn {
                    currentSegment = ""
                    pendingCarriageReturn = false
                }
                currentSegment.unicodeScalars.append(scalar)
            }
        }
    }

    mutating func finish() {
        guard !currentSegment.isEmpty else { return }
        appendOutputLine(ending: "")
        currentSegment = ""
        pendingCarriageReturn = false
    }

    private mutating func appendOutputLine(ending: String) {
        // Transfer status rows drive the progress indicator. History grows by complete output lines.
        guard !updateTransferProgress(from: currentSegment) else { return }
        formattedOutput += currentSegment + ending

        let trimmed = currentSegment.trimmingCharacters(in: .whitespaces)
        if let total = Self.parseTransferStarting(trimmed) {
            totalEntries = total
            if total <= 1 {
                progress = 1.0
            } else if progress == nil {
                progress = 0.0
            }
        } else if !trimmed.isEmpty,
                  !trimmed.hasPrefix("sent "),
                  !trimmed.hasPrefix("total size is "),
                  !trimmed.hasPrefix("building file list"),
                  trimmed != "sending incremental file list",
                  trimmed != "receiving incremental file list" {
            currentTransferFile = trimmed
        }
    }

    @discardableResult
    private mutating func updateTransferProgress(from line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 4,
              tokens[0].first?.isNumber == true,
              tokens[1].hasSuffix("%"),
              let percentage = Int(tokens[1].dropLast()),
              (0...100).contains(percentage),
              tokens[2].hasSuffix("B/s"),
              tokens[3].contains(":") else { return false }

        if tokens.count > 4, let counter = tokens.last,
           let (checked, total) = Self.parseCheckCount(counter) {
            totalEntries = total
            let denominator = max(1, total - 1)
            completedEntries = max(completedEntries, min(checked, denominator))
            progress = min(1.0, Double(completedEntries) / Double(denominator))
        } else {
            let fileFraction = Double(percentage) / 100.0
            if let total = totalEntries, total > 1 {
                progress = min(1.0, (Double(completedEntries) + fileFraction) / Double(total - 1))
            } else {
                progress = fileFraction
            }
        }
        return true
    }

    private static func parseTransferStarting(_ trimmed: String) -> Int? {
        let prefix = "Transfer starting:"
        guard trimmed.hasPrefix(prefix) else { return nil }
        let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let firstToken = rest.split(whereSeparator: \.isWhitespace).first else { return nil }
        return Int(firstToken)
    }

    private static func parseCheckCount(_ counter: Substring) -> (Int, Int)? {
        let field = counter.split(separator: "=", maxSplits: 1)
        guard field.count == 2, field[1].hasSuffix(")") else { return nil }
        let parts = field[1].dropLast().split(separator: "/")
        guard parts.count == 2,
              let checked = Int(parts[0]),
              let total = Int(parts[1]),
              total > 0, (0...total).contains(checked) else { return nil }
        switch field[0] {
        case "to-check": return (checked, total)
        case "to-chk", "ir-chk": return (total - checked, total)
        default: return nil
        }
    }
}

extension SyncTaskViewModel {
    func beginRealtimeProgress(for task: SyncTask, startedAt: Date) -> RealtimeProgressSession? {
        let logID = beginProgressLog(taskID: task.id, startedAt: startedAt)
        var tracker = RsyncProgressTracker()
        let decorateCommand: @MainActor (String) -> String = { command in
            let prefix = "exec /usr/bin/rsync "
            guard !task.arguments.contains("--progress"), command.hasPrefix(prefix) else {
                return command
            }
            return prefix + "--progress " + command.dropFirst(prefix.count)
        }
        let onOutput: @MainActor (String) -> Void = { [weak self] chunk in
            guard let self else { return }
            tracker.ingest(chunk)
            self.applyProgressUpdate(
                tracker.progress,
                file: tracker.currentTransferFile,
                logID: logID,
                output: tracker.formattedOutput
            )
        }
        let finalOutput: @MainActor (String) -> String = { _ in
            tracker.finish()
            return tracker.formattedOutput
        }
        let finalizeLog: @MainActor (String, Bool) -> Void = { [weak self] result, success in
            self?.finalizeProgressLog(logID: logID, taskID: task.id, result: result, success: success)
        }
        let reset: @MainActor () -> Void = { [weak self] in
            self?.resetProgressState()
        }
        return RealtimeProgressSession(
            decorateCommand: decorateCommand,
            onOutput: onOutput,
            finalOutput: finalOutput,
            finalizeLog: finalizeLog,
            reset: reset
        )
    }
}
