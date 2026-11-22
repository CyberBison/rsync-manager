//
//  ShellHelper.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

struct ShellHelper {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Stream output incrementally off the main thread; deliver completion after the pipe closes.
    /// exec replaces the shell so Stop targets rsync itself.
    @MainActor
    static func startCommand(_ command: String,
                             environment: [String: String] = [:],
                             cleanup: (@Sendable () -> Void)? = nil,
                             onOutput: (@MainActor (String) -> Void)? = nil,
                             completion: @escaping @MainActor (String, Int32) -> Void) throws -> Process {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            process.environment = env
        }
        do {
            try process.run()
        } catch {
            cleanup?()
            throw error
        }
        let reader = pipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async {
            var collected = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
                if let onOutput {
                    let text = String(decoding: chunk, as: UTF8.self)
                    DispatchQueue.main.async { onOutput(text) }
                }
            }
            process.waitUntilExit()
            cleanup?()
            let output = String(decoding: collected, as: UTF8.self)
            let code = process.terminationStatus
            DispatchQueue.main.async { completion(output, code) }
        }
        return process
    }

    @discardableResult
    static func runCommand(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

