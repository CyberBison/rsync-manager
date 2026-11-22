//
//  LogEntry.swift
//  rsync-manager
//
//  Created by CyberBison on 24.01.2025.
//

import Foundation

struct LogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let taskId: UUID
    var result: String
    var success: Bool
    var status: String? = nil
}
