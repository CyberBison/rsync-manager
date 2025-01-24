//
//  ShellHelper.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

struct ShellHelper {
    @discardableResult
    static func runCommand(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

