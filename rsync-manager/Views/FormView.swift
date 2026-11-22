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
    @State private var direction: SyncDirection
    @State private var showingDeleteRemovedWarning: Bool
    @State private var showingAdvanced = false
    @FocusState private var nameFocused: Bool

    init(task: SyncTask? = nil, height: CGFloat = 620, onDismiss: @escaping () -> Void, onSave: @escaping (UUID) -> Void = { _ in }) {
        self.task = task
        self.height = height
        self.onDismiss = onDismiss
        self.onSave = onSave
        let initialDirection = task?.direction ?? .oneWay
        let rawArguments = task?.arguments ?? "-av --delete"
        let rawSource = task?.source ?? ""
        let rawDestination = task?.destination ?? ""
        let sanitization = SyncTaskViewModel.sanitizeBiSyncArguments(rawArguments)

        _showingAdvanced = State(initialValue: task != nil)
        _name = State(initialValue: task?.name ?? "")
        _direction = State(initialValue: initialDirection)
        if initialDirection == .biSync {
            _arguments = State(initialValue: sanitization.sanitized)
            _source = State(initialValue: rawSource.isEmpty ? rawSource : SyncTaskViewModel.normalizedBiSyncPath(rawSource))
            _destination = State(initialValue: rawDestination.isEmpty ? rawDestination : SyncTaskViewModel.normalizedBiSyncPath(rawDestination))
            _showingDeleteRemovedWarning = State(initialValue: sanitization.strippedDelete)
        } else {
            _arguments = State(initialValue: rawArguments)
            _source = State(initialValue: rawSource)
            _destination = State(initialValue: rawDestination)
            _showingDeleteRemovedWarning = State(initialValue: false)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !source.isEmpty && !destination.isEmpty
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
                Section("Folders") {
                    FolderPicker(label: "Source", path: $source)
                    FolderPicker(label: "Destination", path: $destination)
                    if direction == .oneWay {
                        Text("A trailing slash on the source copies its contents. Without it, rsync copies the folder itself.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Bi-sync normalizes both folder paths with a trailing slash to keep their contents synchronized symmetrically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Behaviour") {
                    HStack(spacing: 8) {
                        Image(systemName: direction.symbolName)
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                        Picker("Sync Behavior", selection: $direction) {
                            ForEach(SyncDirection.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Sync behavior")
                        .accessibilityIdentifier("syncDirectionPicker")
                        Spacer()
                    }
                    if direction == .oneWay {
                        if SyncTaskViewModel.containsDeleteFlag(arguments) {
                            Label {
                                Text("Destination files missing from the source can be deleted.")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            }.font(.callout)
                        }
                    } else {
                        if showingDeleteRemovedWarning || SyncTaskViewModel.containsDeleteFlag(arguments) {
                            Label {
                                Text("The --delete flag is removed when Bi-Sync is selected to prevent deleting files before both folders are synced.")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            }.font(.callout)
                        }
                        Label("Newer files on either side update the other (--update). Single-side deletions are tracked after the initial sync.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout).foregroundStyle(.secondary)
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
        .onAppear { nameFocused = true }
        .onChange(of: direction) { _, newDirection in
            if newDirection == .biSync {
                if !source.isEmpty {
                    source = SyncTaskViewModel.normalizedBiSyncPath(source)
                }
                if !destination.isEmpty {
                    destination = SyncTaskViewModel.normalizedBiSyncPath(destination)
                }
                let result = SyncTaskViewModel.sanitizeBiSyncArguments(arguments)
                arguments = result.sanitized
                if result.strippedDelete {
                    showingDeleteRemovedWarning = true
                }
            } else {
                showingDeleteRemovedWarning = false
                if arguments == "-avu" || arguments == "-av -u" {
                    arguments = "-av --delete"
                }
            }
        }
    }

    private func save() {
        var finalSource = source
        var finalDestination = destination
        var finalArguments = arguments
        if direction == .biSync {
            finalSource = SyncTaskViewModel.normalizedBiSyncPath(source)
            finalDestination = SyncTaskViewModel.normalizedBiSyncPath(destination)
            finalArguments = SyncTaskViewModel.sanitizeBiSyncArguments(arguments).sanitized
        }
        if let task {
            viewModel.updateTask(task, name: name, arguments: finalArguments, source: finalSource, destination: finalDestination, direction: direction)
            onSave(task.id)
        } else {
            viewModel.addTask(name: name, arguments: finalArguments, source: finalSource, destination: finalDestination, direction: direction)
            if let id = viewModel.tasks.last?.id { onSave(id) }
        }
        viewModel.saveTasks()
        onDismiss()
    }
}
