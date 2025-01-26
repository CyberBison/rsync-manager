//
//  SyncTask.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

struct SyncTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var arguments: String
    var source: String
    var destination: String
    var lastSyncDate: Date?
    var lastSyncStatus: String?
    var isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, arguments, source, destination, lastSyncDate, lastSyncStatus, isActive
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? "-av --delete" // In version 1.0.0, the command was always set to -av --delete. Adding this for backwards compatibility.
        self.source = try container.decode(String.self, forKey: .source)
        self.destination = try container.decode(String.self, forKey: .destination)
        self.lastSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        self.lastSyncStatus = try container.decodeIfPresent(String.self, forKey: .lastSyncStatus)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(source, forKey: .source)
        try container.encode(destination, forKey: .destination)
        try container.encode(lastSyncDate, forKey: .lastSyncDate)
        try container.encode(lastSyncStatus, forKey: .lastSyncStatus)
        try container.encode(isActive, forKey: .isActive)
    }
    
    init(id: UUID, name: String, arguments: String, source: String, destination: String, lastSyncDate: Date?, lastSyncStatus: String?, isActive: Bool) {
            self.id = id
            self.name = name
            self.arguments = arguments
            self.source = source
            self.destination = destination
            self.lastSyncDate = lastSyncDate
            self.lastSyncStatus = lastSyncStatus
            self.isActive = isActive
        }
}
