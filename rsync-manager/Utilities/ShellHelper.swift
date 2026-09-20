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

    /// Drain output off the main thread; deliver completion after the pipe closes.
    /// exec replaces the shell so Stop targets rsync itself.
    @MainActor
    static func startCommand(_ command: String,
                             completion: @escaping @MainActor (String, Int32) -> Void) throws -> Process {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        try process.run()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
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

