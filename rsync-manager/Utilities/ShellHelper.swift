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
                             environment: [String: String] = [:],
                             cleanup: (@Sendable () -> Void)? = nil,
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
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            cleanup?()
            let output = String(decoding: data, as: UTF8.self)
            let code = process.terminationStatus
            DispatchQueue.main.async { completion(output, code) }
        }
        return process
    }

    static func makeSSHAskPassScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rsync-askpass-\(UUID().uuidString).sh")
        let script = "#!/bin/zsh\nprintf '%s\\n' \"$RSYNC_SSH_PASSWORD\"\n"
        try Data(script.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
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

