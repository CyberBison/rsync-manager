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
    private var totalEntries: Int?
    private var completedEntries = 0
    private var currentFileFraction = 0.0

    private var completedLines: [String] = []
    private var currentSegment = ""
    private var pendingCarriageReturn = false

    var formattedOutput: String {
        var lines = completedLines
        if !currentSegment.isEmpty {
            lines.append(currentSegment)
            return lines.joined(separator: "\n")
        }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    mutating func ingest(_ chunk: String) {
        for scalar in chunk.unicodeScalars {
            switch scalar {
            case "\r":
                if !currentSegment.isEmpty {
                    parseLine(currentSegment)
                }
                pendingCarriageReturn = true
            case "\n":
                let wasCarriageReturn = pendingCarriageReturn
                pendingCarriageReturn = false
                if !wasCarriageReturn || !currentSegment.isEmpty {
                    if !wasCarriageReturn {
                        parseLine(currentSegment)
                    }
                    completedLines.append(currentSegment)
                } else {
                    completedLines.append("")
                }
                currentSegment = ""
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
        if !currentSegment.isEmpty && !pendingCarriageReturn {
            parseLine(currentSegment)
        }
    }

    private mutating func parseLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let total = Self.parseTransferStarting(trimmed) {
            totalEntries = total
            if total <= 1 {
                progress = 1.0
            } else if progress == nil {
                progress = 0.0
            }
            return
        }

        if let (checkedIndex, total) = Self.parseToCheck(trimmed) {
            totalEntries = total
            let denominator = max(1, total - 1)
            completedEntries = max(completedEntries, min(checkedIndex, denominator))
            currentFileFraction = 0
            progress = min(1.0, Double(completedEntries) / Double(denominator))
            return
        }

        if let filePercentage = Self.parseInProgressPercentage(rawLine: line, trimmed: trimmed) {
            currentFileFraction = Double(filePercentage) / 100.0
            if let total = totalEntries, total > 1 {
                progress = min(1.0, (Double(completedEntries) + currentFileFraction) / Double(total - 1))
            } else {
                progress = min(1.0, max(0.0, currentFileFraction))
            }
            return
        }

        if !trimmed.hasPrefix("sent "),
           !trimmed.hasPrefix("total size is "),
           !trimmed.hasPrefix("building file list") {
            currentTransferFile = trimmed
        }
    }

    private static func parseTransferStarting(_ trimmed: String) -> Int? {
        let prefix = "Transfer starting:"
        guard trimmed.hasPrefix(prefix) else { return nil }
        let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let firstToken = rest.split(whereSeparator: \.isWhitespace).first else { return nil }
        return Int(firstToken)
    }

    private static func parseToCheck(_ trimmed: String) -> (Int, Int)? {
        guard let range = trimmed.range(of: "to-check=") else { return nil }
        let after = trimmed[range.upperBound...]
        let token = after.prefix { $0.isNumber || $0 == "/" }
        let parts = token.split(separator: "/")
        guard parts.count == 2,
              let checked = Int(parts[0]),
              let total = Int(parts[1]),
              total > 0 else { return nil }
        return (checked, total)
    }

    private static func parseInProgressPercentage(rawLine: String, trimmed: String) -> Int? {
        guard !trimmed.contains("to-check=") else { return nil }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 2,
              let pctToken = tokens.first(where: { $0.hasSuffix("%") }),
              let pct = Int(pctToken.dropLast()),
              (0...100).contains(pct) else { return nil }
        let hasRate = trimmed.contains("B/s")
        let startsWithWhitespaceAndBytes = (rawLine.first?.isWhitespace ?? false) &&
            Int64(tokens[0].replacingOccurrences(of: ",", with: "")) != nil
        guard hasRate || startsWithWhitespaceAndBytes else { return nil }
        return pct
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
        let finalOutput: @MainActor (String) -> String = { output in
            tracker.finish()
            return tracker.formattedOutput.isEmpty ? output : tracker.formattedOutput
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
