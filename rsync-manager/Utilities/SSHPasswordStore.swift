import Foundation
import Security

struct SSHPasswordStore {
    private let storageDirectory: URL?
    private let serviceName = "io.cyberbison.rsync-manager.ssh"
    private let testFileName = "ssh_passwords.json"

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
    }

    func password(for taskID: UUID) -> String? {
        if let storageDirectory {
            return loadTestPasswords(in: storageDirectory)[taskID.uuidString]
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: taskID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String, for taskID: UUID) {
        if password.isEmpty {
            deletePassword(for: taskID)
            return
        }

        if let storageDirectory {
            var dict = loadTestPasswords(in: storageDirectory)
            dict[taskID.uuidString] = password
            saveTestPasswords(dict, in: storageDirectory)
            return
        }

        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: taskID.uuidString
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func deletePassword(for taskID: UUID) {
        if let storageDirectory {
            var dict = loadTestPasswords(in: storageDirectory)
            dict.removeValue(forKey: taskID.uuidString)
            saveTestPasswords(dict, in: storageDirectory)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: taskID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadTestPasswords(in directory: URL) -> [String: String] {
        let url = directory.appendingPathComponent(testFileName)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveTestPasswords(_ dict: [String: String], in directory: URL) {
        let url = directory.appendingPathComponent(testFileName)
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
