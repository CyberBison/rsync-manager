import AppKit
import SwiftUI

struct FormView: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
    let task: SyncTask?
    let height: CGFloat
    let onDismiss: () -> Void
    let onSave: (UUID) -> Void
    @State private var name: String
    @State private var arguments: String
    @State private var source: String
    @State private var destination: String
    @State private var sourceType: EndpointLocationType
    @State private var destinationType: EndpointLocationType
    @State private var sshHost: String
    @State private var sshUser: String
    @State private var sshPortText: String
    @State private var sshRemotePath: String
    @State private var sshAuthMethod: SSHAuthMethod
    @State private var sshKeyPath: String
    @State private var sshCertificatePath: String
    @State private var sshPassword: String
    @State private var passwordLoaded = false
    @State private var showingAdvanced = false
    @FocusState private var nameFocused: Bool

    init(task: SyncTask? = nil, height: CGFloat = 620, onDismiss: @escaping () -> Void, onSave: @escaping (UUID) -> Void = { _ in }) {
        self.task = task
        self.height = height
        self.onDismiss = onDismiss
        self.onSave = onSave
        _showingAdvanced = State(initialValue: task != nil)
        _name = State(initialValue: task?.name ?? "")
        _arguments = State(initialValue: task?.arguments ?? "-av --delete")
        let initialSourceType = task?.sourceType ?? .local
        let initialDestinationType = task?.destinationType ?? .local
        _sourceType = State(initialValue: initialSourceType)
        _destinationType = State(initialValue: initialDestinationType)
        _source = State(initialValue: initialSourceType == .ssh ? "" : (task?.source ?? ""))
        _destination = State(initialValue: initialDestinationType == .ssh ? "" : (task?.destination ?? ""))

        let ssh = task?.sshConfiguration ?? SSHConfiguration()
        _sshHost = State(initialValue: ssh.host)
        _sshUser = State(initialValue: ssh.user)
        _sshPortText = State(initialValue: ssh.port.map(String.init) ?? "")
        _sshRemotePath = State(initialValue: ssh.remotePath)
        _sshAuthMethod = State(initialValue: ssh.authMethod)
        _sshKeyPath = State(initialValue: ssh.keyPath)
        _sshCertificatePath = State(initialValue: ssh.certificatePath)
        _sshPassword = State(initialValue: "")
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !(sourceType == .ssh && destinationType == .ssh) else { return false }

        if sourceType == .local && source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if destinationType == .local && destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if sourceType == .ssh || destinationType == .ssh {
            if sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if sshRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            let trimmedPort = sshPortText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPort.isEmpty {
                guard let port = Int(trimmedPort), port > 0, port <= 65535 else { return false }
            }
            switch sshAuthMethod {
            case .sshAgent:
                break
            case .publicKey:
                if sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            case .password:
                if sshPassword.isEmpty { return false }
            case .certificate:
                if sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
                if sshCertificatePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task == nil ? "New Profile" : "Edit Profile").font(.title2.weight(.semibold))
                    Text("Choose what to sync and where it should go.").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Form {
                Section("Profile") {
                    TextField("Name", text: $name, prompt: Text("For example, Documents Backup"))
                        .focused($nameFocused)
                        .accessibilityLabel("Name")
                }
                Section("Source") {
                    Picker("Source Type", selection: $sourceType) {
                        ForEach(EndpointLocationType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sourceTypePicker")

                    if sourceType == .local {
                        FolderPicker(label: "Source", path: $source)
                    } else {
                        sshEndpointFields(role: "Source")
                    }
                }
                Section("Destination") {
                    Picker("Destination Type", selection: $destinationType) {
                        ForEach(EndpointLocationType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("destinationTypePicker")

                    if destinationType == .local {
                        FolderPicker(label: "Destination", path: $destination)
                    } else {
                        sshEndpointFields(role: "Destination")
                    }
                    Text("A trailing slash on the source copies its contents. Without it, rsync copies the folder itself.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Behaviour") {
                    Label("One-way sync", systemImage: "arrow.right")
                    if arguments.contains("--delete") {
                        Label {
                            Text("Destination files missing from the source can be deleted.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        }.font(.callout)
                    }
                    DisclosureGroup("Advanced arguments & exclusions", isExpanded: $showingAdvanced) {
                        TextField("Arguments", text: $arguments, axis: .vertical)
                            .font(.system(.body, design: .monospaced)).lineLimit(3...8)
                            .accessibilityIdentifier("argumentsField")
                        Text("All existing rsync flags are supported. Add exclusions here, for example --exclude='*.tmp'.")
                            .font(.caption).foregroundStyle(.secondary)
                        RsyncGuideLink()
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel", action: onDismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button(task == nil ? "Create Profile" : "Save Changes", action: save)
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(20)
        }
        .frame(width: 580, height: height)
        .onChange(of: sourceType) { _, newValue in
            if newValue == .ssh && destinationType == .ssh {
                destinationType = .local
            }
        }
        .onChange(of: destinationType) { _, newValue in
            if newValue == .ssh && sourceType == .ssh {
                sourceType = .local
            }
        }
        .onAppear {
            nameFocused = true
            if let task, !passwordLoaded, task.sshConfiguration?.usesPassword == true {
                sshPassword = viewModel.passwordStore.password(for: task.id) ?? ""
                passwordLoaded = true
            }
        }
    }

    @ViewBuilder
    private func sshEndpointFields(role: String) -> some View {
        LabeledContent("SSH Host") {
            TextField("", text: $sshHost, prompt: Text("hostname or IP address"))
                .accessibilityLabel("SSH Host")
                .accessibilityIdentifier("sshHostField")
        }

        TextField("SSH Port", text: $sshPortText, prompt: Text("22"))
            .accessibilityLabel("SSH Port")
            .accessibilityIdentifier("sshPortField")

        LabeledContent("\(role) Path") {
            TextField("", text: $sshRemotePath, prompt: Text("/path/on/remote or ~/folder"))
                .accessibilityLabel("\(role) path")
                .accessibilityIdentifier("sshRemotePathField")
        }

        Picker("Authentication", selection: $sshAuthMethod) {
            ForEach(SSHAuthMethod.allCases, id: \.self) { method in
                Text(method.title).tag(method)
            }
        }
        .accessibilityIdentifier("sshAuthMethodPicker")

        TextField("SSH User", text: $sshUser, prompt: Text("Optional username"))
            .accessibilityLabel("SSH User")
            .accessibilityIdentifier("sshUserField")

        switch sshAuthMethod {
        case .sshAgent:
            Text("Uses keys loaded in your macOS SSH agent (ssh-agent) or default ~/.ssh configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .publicKey:
            privateKeyFieldRow
            Text("Authenticates using the selected SSH private key file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .password:
            SecureField("SSH Password", text: $sshPassword, prompt: Text("Stored securely in macOS Keychain"))
                .accessibilityLabel("SSH Password")
                .accessibilityIdentifier("sshPasswordField")
            Text("Authenticates using a password stored securely in your macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .certificate:
            privateKeyFieldRow
            certificateFieldRow
            Text("Authenticates using an OpenSSH signed user certificate (*-cert.pub) and its matching private key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var privateKeyFieldRow: some View {
        sshFilePickerRow(
            label: "Private Key",
            path: $sshKeyPath,
            placeholder: "Choose or enter a private key path",
            accessibilityLabel: "SSH Key Path",
            identifier: "sshKeyPathField",
            panelTitle: "Choose SSH Private Key"
        )
    }

    @ViewBuilder
    private var certificateFieldRow: some View {
        sshFilePickerRow(
            label: "Certificate",
            path: $sshCertificatePath,
            placeholder: "Choose or enter a *-cert.pub path",
            accessibilityLabel: "SSH Certificate Path",
            identifier: "sshCertificatePathField",
            panelTitle: "Choose SSH Certificate"
        )
    }

    @ViewBuilder
    private func sshFilePickerRow(
        label: String,
        path: Binding<String>,
        placeholder: String,
        accessibilityLabel: String,
        identifier: String,
        panelTitle: String
    ) -> some View {
        LabeledContent(label) {
            HStack {
                TextField("", text: path, prompt: Text(placeholder))
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityIdentifier(identifier)
                Button("Choose…") {
                    chooseSSHFile(title: panelTitle) { selected in
                        path.wrappedValue = selected
                    }
                }
                .accessibilityLabel("Choose \(label.lowercased())")
            }
        }
    }

    private func chooseSSHFile(title: String, onSelect: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        if viewModel.sshAccessManager.realSSHDirectoryExists {
            panel.directoryURL = viewModel.sshAccessManager.realSSHDirectoryURL
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    viewModel.sshAccessManager.bookmarkFile(url)
                    onSelect(url.path)
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            viewModel.sshAccessManager.bookmarkFile(url)
            onSelect(url.path)
        }
    }

    private func save() {
        let isSSH = sourceType == .ssh || destinationType == .ssh
        let trimmedPort = sshPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPort = trimmedPort.isEmpty ? nil : Int(trimmedPort)
        let usesKey = sshAuthMethod == .publicKey || sshAuthMethod == .certificate

        let sshConfig: SSHConfiguration? = isSSH ? SSHConfiguration(
            host: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
            user: sshUser.trimmingCharacters(in: .whitespacesAndNewlines),
            port: parsedPort,
            remotePath: sshRemotePath.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: sshAuthMethod,
            keyPath: usesKey ? sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            certificatePath: sshAuthMethod == .certificate ? sshCertificatePath.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        ) : nil

        let commitSave: @MainActor () -> Void = {
            let resolvedSource = sourceType == .ssh ? (sshConfig?.formattedEndpoint ?? "") : source
            let resolvedDestination = destinationType == .ssh ? (sshConfig?.formattedEndpoint ?? "") : destination
            let passwordToSave = (isSSH && sshAuthMethod == .password) ? sshPassword : nil

            if let task {
                viewModel.updateTask(
                    task,
                    name: name,
                    arguments: arguments,
                    source: resolvedSource,
                    destination: resolvedDestination,
                    sourceType: sourceType,
                    destinationType: destinationType,
                    sshConfiguration: sshConfig,
                    sshPassword: passwordToSave
                )
                onSave(task.id)
            } else {
                viewModel.addTask(
                    name: name,
                    arguments: arguments,
                    source: resolvedSource,
                    destination: resolvedDestination,
                    sourceType: sourceType,
                    destinationType: destinationType,
                    sshConfiguration: sshConfig,
                    sshPassword: passwordToSave
                )
                if let id = viewModel.tasks.last?.id { onSave(id) }
            }
            viewModel.saveTasks()
            onDismiss()
        }

        guard let sshConfig else {
            commitSave()
            return
        }

        switch sshConfig.authMethod {
        case .sshAgent:
            viewModel.sshAccessManager.ensureSSHAgentAccess(
                host: sshConfig.host,
                user: sshConfig.user,
                port: sshConfig.port
            ) { granted in
                if granted { commitSave() }
            }
        case .publicKey:
            viewModel.sshAccessManager.ensureExplicitCredentialFilesAccess(
                paths: [sshConfig.keyPath]
            ) { granted in
                if granted { commitSave() }
            }
        case .certificate:
            viewModel.sshAccessManager.ensureExplicitCredentialFilesAccess(
                paths: [sshConfig.keyPath, sshConfig.certificatePath]
            ) { granted in
                if granted { commitSave() }
            }
        case .password:
            commitSave()
        }
    }
}
