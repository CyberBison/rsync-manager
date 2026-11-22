import Foundation
import Testing
@testable import rsync_manager

struct rsync_managerTests {
    @Test func legacyProfileStillLoads() throws {
        let data = Data("""
        {"id":"AA747039-EA72-4BDA-BA78-5D4D50604121","name":"Backup","source":"/a","destination":"/b","isActive":true}
        """.utf8)
        let profile = try JSONDecoder().decode(SyncTask.self, from: data)
        #expect(profile.arguments == "-av --delete")
        #expect(try JSONDecoder().decode(SyncTask.self, from: JSONEncoder().encode(profile)) == profile)
    }

    @Test func shellPathsRemainLiteral() throws {
        let path = "/tmp/it's a folder/$(echo should-not-expand);name"
        let output = try ShellHelper.runCommand("printf %s \(ShellHelper.quote(path))")
        #expect(output == path)
    }

    @Test func legacyErrorLogsArePresentedAsFailures() {
        let log = LogEntry(id: UUID(), timestamp: Date(), taskId: UUID(), result: "rsync error: permission denied", success: true)
        #expect(log.displayStatus == "error")
    }

    @MainActor @Test func asyncCommandReportsExitStatus() async throws {
        let result: (String, Int32) = try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try ShellHelper.startCommand("printf 'failure output'; exit 23") { output, status in
                    continuation.resume(returning: (output, status))
                }
            } catch { continuation.resume(throwing: error) }
        }
        #expect(result.0 == "failure output")
        #expect(result.1 == 23)
    }

    @MainActor @Test func stopTerminatesRunningProcess() async throws {
        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            do {
                let process = try ShellHelper.startCommand("exec /bin/sleep 30") { _, code in
                    continuation.resume(returning: code)
                }
                process.terminate()
            } catch { continuation.resume(throwing: error) }
        }
        #expect(code != 0)
    }

    @MainActor @Test func syncCopiesFilesAndRecordsFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("source with ' quote")
        let destination = directory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("A safe test file".utf8).write(to: source.appendingPathComponent("sample.txt"))
        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "Integration", arguments: "-av", source: source.path + "/", destination: destination.path)
        model.runSync(task: try #require(model.tasks.first))
        for _ in 0..<100 where model.runningTaskID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.runningTaskID == nil)
        #expect(model.logs.last?.success == true)
        #expect(try String(contentsOf: destination.appendingPathComponent("sample.txt"), encoding: .utf8) == "A safe test file")
        var missingSource = try #require(model.tasks.first)
        missingSource.source = directory.appendingPathComponent("missing").path
        model.runSync(task: missingSource)
        for _ in 0..<100 where model.runningTaskID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.logs.last?.success == false)
        #expect(model.tasks.first?.lastSyncStatus == "error")
    }

    @MainActor @Test func profilesPersistWithoutChangingTheirSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = SyncTaskViewModel(storageDirectory: directory)
        model.addTask(name: "Photos", arguments: "-av --exclude='*.tmp'", source: "/source/", destination: "/destination")
        model.saveTasks()
        let restored = SyncTaskViewModel(storageDirectory: directory)
        #expect(restored.tasks == model.tasks)
        let original = try #require(restored.tasks.first)
        restored.updateTask(original, name: "Renamed", arguments: "--dry-run", source: "/new/", destination: "/backup")
        #expect(restored.tasks.first?.id == original.id)
        #expect(restored.tasks.first?.arguments == "--dry-run")
    }

    @MainActor @Test func sshCommandGenerationAndPasswordStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rsync-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = SyncTaskViewModel(storageDirectory: directory)
        let passwordSSH = SSHConfiguration(
            host: "studio.local",
            user: "backup",
            port: 2222,
            remotePath: "/archive",
            authMethod: .password
        )

        model.addTask(
            name: "Remote Backup",
            arguments: "-avz",
            source: "/Users/example/Docs/",
            destination: "",
            sourceType: .local,
            destinationType: .ssh,
            sshConfiguration: passwordSSH,
            sshPassword: "secret-pass"
        )
        model.saveTasks()

        let task = try #require(model.tasks.first)
        #expect(task.destinationType == .ssh)
        #expect(task.destination == "backup@studio.local:/archive")
        #expect(model.passwordStore.password(for: task.id) == "secret-pass")

        let passwordCommand = model.buildRsyncCommand(for: task)
        #expect(passwordCommand.contains("-e "))
        #expect(passwordCommand.contains("/usr/bin/ssh"))
        #expect(passwordCommand.contains("-p 2222"))
        #expect(passwordCommand.contains("PreferredAuthentications=keyboard-interactive,password"))
        #expect(passwordCommand.contains("PubkeyAuthentication=no"))
        #expect(passwordCommand.contains("NumberOfPasswordPrompts=1"))
        #expect(passwordCommand.contains("'backup@studio.local:/archive'"))

        let restored = SyncTaskViewModel(storageDirectory: directory)
        #expect(restored.tasks == model.tasks)

        let publicKeySSH = SSHConfiguration(
            host: "studio.local",
            user: "backup",
            port: 2222,
            remotePath: "/archive",
            authMethod: .publicKey,
            keyPath: "/tmp/id_ed25519"
        )
        restored.updateTask(
            task,
            name: "Remote Backup",
            arguments: "-avz",
            source: "/Users/example/Docs/",
            destination: "",
            sourceType: .local,
            destinationType: .ssh,
            sshConfiguration: publicKeySSH
        )
        let updatedTask = try #require(restored.tasks.first)
        #expect(restored.passwordStore.password(for: task.id) == nil)
        let publicKeySSHCommand = restored.buildSSHCommand(for: publicKeySSH)
        #expect(publicKeySSHCommand.contains("-i '/tmp/id_ed25519'"))
        #expect(publicKeySSHCommand.contains("IdentitiesOnly=yes"))
        #expect(publicKeySSHCommand.contains("BatchMode=yes"))
        let publicKeyRsyncCommand = restored.buildRsyncCommand(for: updatedTask)
        #expect(publicKeyRsyncCommand.contains("/tmp/id_ed25519"))
        #expect(publicKeyRsyncCommand.contains("BatchMode=yes"))

        let certificateSSH = SSHConfiguration(
            host: "studio.local",
            user: "backup",
            port: 2222,
            remotePath: "/archive",
            authMethod: .certificate,
            keyPath: "/tmp/id_ed25519",
            certificatePath: "/tmp/id_ed25519-cert.pub"
        )
        let certificateCommand = restored.buildSSHCommand(for: certificateSSH)
        #expect(certificateCommand.contains("-i '/tmp/id_ed25519'"))
        #expect(certificateCommand.contains("-o CertificateFile='/tmp/id_ed25519-cert.pub'"))
        #expect(certificateCommand.contains("IdentitiesOnly=yes"))
        #expect(certificateCommand.contains("BatchMode=yes"))

        let agentSSH = SSHConfiguration(
            host: "studio.local",
            user: "backup",
            remotePath: "/archive",
            authMethod: .sshAgent
        )
        let agentCommand = restored.buildSSHCommand(for: agentSSH)
        #expect(agentCommand.contains("-o StrictHostKeyChecking=accept-new"))
        #expect(agentCommand.contains("-o BatchMode=yes"))
        #expect(!agentCommand.contains("-i "))
        #expect(!agentCommand.contains("CertificateFile"))
        #expect(!agentCommand.contains("UserKnownHostsFile="))

        let fallbackAgentCommand = restored.buildSSHCommand(for: agentSSH, hasSSHDirAccess: false)
        #expect(fallbackAgentCommand.contains("UserKnownHostsFile="))
        #expect(model.sshAccessManager.expandRealHomePath("~/.ssh/id_ed25519").hasSuffix("/.ssh/id_ed25519"))

        restored.deleteTask(updatedTask)
        #expect(restored.tasks.isEmpty)
        #expect(restored.passwordStore.password(for: task.id) == nil)
    }

    @MainActor @Test func sshConfigMatchingFiltersByHostAndUserAndDefaultUser() {
        let manager = SSHSandboxAccessManager()
        let configText = """
        # SSH configuration with multiple hosts and users
        Host server1.example.com
          HostName server1.example.com
          User ubuntu
          IdentityFile ~/Documents/keys/ubuntu_key

        Host server1.example.com
          User deploy
          IdentityFile ~/Documents/keys/deploy_key

        Host server1.example.com
          User macuser
          IdentityFile ~/Documents/keys/macuser_%h_%r_%u_%p_%%.key

        Host other.example.com
          User ubuntu
          IdentityFile ~/Documents/keys/other_host_key

        Host *
          User otheruser
          IdentityFile ~/Documents/keys/other_global_key

        Match host *.internal user ubuntu
          CertificateFile /tmp/certs/%r-cert.pub
        """

        let ubuntuPaths = manager.matchingConfigCredentialPaths(
            inConfigText: configText,
            host: "server1.example.com",
            user: "ubuntu",
            port: 2222,
            defaultUser: "macuser"
        )
        #expect(ubuntuPaths == [manager.expandRealHomePath("~/Documents/keys/ubuntu_key")])

        let emptyUserFallbackPaths = manager.matchingConfigCredentialPaths(
            inConfigText: configText,
            host: "server1.example.com",
            user: "",
            port: 2222,
            defaultUser: "macuser"
        )
        #expect(emptyUserFallbackPaths == [manager.expandRealHomePath("~/Documents/keys/macuser_server1.example.com_macuser_macuser_2222_%.key")])

        let matchPaths = manager.matchingConfigCredentialPaths(
            inConfigText: configText,
            host: "db.internal",
            user: "ubuntu",
            port: nil,
            defaultUser: "macuser"
        )
        #expect(matchPaths == ["/tmp/certs/ubuntu-cert.pub"])

        let hostAliasConfig = """
        Host *
          IdentityFile ~/.ssh/id_ed25519

        Host prod-alias
          HostName 203.0.113.10
          User deploy
          IdentityFile ~/Documents/keys/prod_%h_%r_%u_%p.key
        """
        let aliasFallbackPaths = manager.matchingConfigCredentialPaths(
            inConfigText: hostAliasConfig,
            host: "prod-alias",
            user: "",
            port: nil,
            defaultUser: "macuser"
        )
        #expect(aliasFallbackPaths == [
            manager.expandRealHomePath("~/.ssh/id_ed25519"),
            manager.expandRealHomePath("~/Documents/keys/prod_203.0.113.10_deploy_macuser_22.key")
        ])
    }

    @Test func legacySSHProfileInference() throws {
        let data = Data("""
        {"id":"AA747039-EA72-4BDA-BA78-5D4D50604122","name":"Remote","arguments":"-avz","source":"/Users/example/Projects/","destination":"backup@studio.local:/archive/projects","isActive":true}
        """.utf8)
        let profile = try JSONDecoder().decode(SyncTask.self, from: data)
        #expect(profile.sourceType == .local)
        #expect(profile.destinationType == .ssh)
        #expect(profile.sshConfiguration?.host == "studio.local")
        #expect(profile.sshConfiguration?.user == "backup")
        #expect(profile.sshConfiguration?.remotePath == "/archive/projects")
    }
}
