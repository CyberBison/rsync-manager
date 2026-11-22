//
//  SyncTask.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import Foundation

enum EndpointLocationType: String, Codable, Equatable, CaseIterable {
    case local
    case ssh

    var title: String {
        switch self {
        case .local: "Local"
        case .ssh: "SSH"
        }
    }
}

enum SSHAuthMethod: String, Codable, Equatable, CaseIterable {
    case sshAgent
    case publicKey
    case password
    case certificate

    var title: String {
        switch self {
        case .sshAgent: "SSH Agent"
        case .publicKey: "Public Key"
        case .password: "Password"
        case .certificate: "Certificate"
        }
    }
}

struct SSHConfiguration: Codable, Equatable {
    var host: String
    var user: String
    var port: Int?
    var remotePath: String
    var authMethod: SSHAuthMethod
    var keyPath: String
    var certificatePath: String

    init(
        host: String = "",
        user: String = "",
        port: Int? = nil,
        remotePath: String = "",
        authMethod: SSHAuthMethod = .sshAgent,
        keyPath: String = "",
        certificatePath: String = ""
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.remotePath = remotePath
        self.authMethod = authMethod
        self.keyPath = keyPath
        self.certificatePath = certificatePath
    }

    var usesPassword: Bool {
        authMethod == .password
    }

    var formattedEndpoint: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostPart = trimmedUser.isEmpty ? trimmedHost : "\(trimmedUser)@\(trimmedHost)"
        return "\(hostPart):\(remotePath)"
    }

    var authSummary: String {
        switch authMethod {
        case .sshAgent:
            return "SSH Agent"
        case .publicKey:
            let name = (keyPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent
            return name.isEmpty ? "Public Key" : "Public Key (\(name))"
        case .password:
            return "Password"
        case .certificate:
            let name = (certificatePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent
            return name.isEmpty ? "Certificate" : "Certificate (\(name))"
        }
    }

    static func parseLegacyEndpoint(_ spec: String) -> SSHConfiguration? {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.hasPrefix("."),
              let colonIndex = trimmed.firstIndex(of: ":") else {
            return nil
        }
        let userHost = String(trimmed[..<colonIndex])
        guard !userHost.isEmpty, !userHost.contains("/") else { return nil }
        let remotePath = String(trimmed[trimmed.index(after: colonIndex)...])
        if let atIndex = userHost.firstIndex(of: "@") {
            let user = String(userHost[..<atIndex])
            let host = String(userHost[userHost.index(after: atIndex)...])
            guard !host.isEmpty else { return nil }
            return SSHConfiguration(host: host, user: user, remotePath: remotePath)
        } else {
            return SSHConfiguration(host: userHost, user: "", remotePath: remotePath)
        }
    }
}

struct SyncTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var arguments: String
    var source: String
    var destination: String
    var lastSyncDate: Date?
    var lastSyncStatus: String?
    var isActive: Bool
    var sourceType: EndpointLocationType
    var destinationType: EndpointLocationType
    var sshConfiguration: SSHConfiguration?

    var usesSSH: Bool {
        sourceType == .ssh || destinationType == .ssh
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, arguments, source, destination, lastSyncDate, lastSyncStatus, isActive
        case sourceType, destinationType, sshConfiguration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? "-av --delete" // In version 1.0.0, the command was always set to -av --delete. Adding this for backwards compatibility.
        let decodedSource = try container.decode(String.self, forKey: .source)
        let decodedDestination = try container.decode(String.self, forKey: .destination)
        self.source = decodedSource
        self.destination = decodedDestination
        self.lastSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        self.lastSyncStatus = try container.decodeIfPresent(String.self, forKey: .lastSyncStatus)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)

        let decodedSourceType = try container.decodeIfPresent(EndpointLocationType.self, forKey: .sourceType)
        let decodedDestinationType = try container.decodeIfPresent(EndpointLocationType.self, forKey: .destinationType)
        let decodedSSH = try container.decodeIfPresent(SSHConfiguration.self, forKey: .sshConfiguration)

        if decodedSourceType == nil && decodedDestinationType == nil && decodedSSH == nil {
            if let parsedSource = SSHConfiguration.parseLegacyEndpoint(decodedSource) {
                self.sourceType = .ssh
                self.destinationType = .local
                self.sshConfiguration = parsedSource
            } else if let parsedDestination = SSHConfiguration.parseLegacyEndpoint(decodedDestination) {
                self.sourceType = .local
                self.destinationType = .ssh
                self.sshConfiguration = parsedDestination
            } else {
                self.sourceType = .local
                self.destinationType = .local
                self.sshConfiguration = nil
            }
        } else {
            self.sourceType = decodedSourceType ?? .local
            self.destinationType = decodedDestinationType ?? .local
            self.sshConfiguration = decodedSSH
        }
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
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(destinationType, forKey: .destinationType)
        try container.encodeIfPresent(sshConfiguration, forKey: .sshConfiguration)
    }
    
    init(
        id: UUID,
        name: String,
        arguments: String,
        source: String,
        destination: String,
        lastSyncDate: Date?,
        lastSyncStatus: String?,
        isActive: Bool,
        sourceType: EndpointLocationType = .local,
        destinationType: EndpointLocationType = .local,
        sshConfiguration: SSHConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.source = source
        self.destination = destination
        self.lastSyncDate = lastSyncDate
        self.lastSyncStatus = lastSyncStatus
        self.isActive = isActive
        self.sourceType = sourceType
        self.destinationType = destinationType
        self.sshConfiguration = sshConfiguration
    }
}
