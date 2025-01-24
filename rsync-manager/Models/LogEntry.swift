//
//  LogEntry.swift
//  rsync-manager
//
//  Created by CyberBison on 24.01.2025.
//

import Foundation

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let taskId: UUID
    let result: String
    let success: Bool
}
