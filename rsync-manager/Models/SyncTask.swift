//
//  SyncTask.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

struct SyncTask: Identifiable, Codable {
    let id: UUID
    var source: String
    var destination: String
    var lastSyncDate: Date?
    var isActive: Bool
}
