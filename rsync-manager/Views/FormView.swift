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
        _source = State(initialValue: task?.source ?? "")
        _destination = State(initialValue: task?.destination ?? "")
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
        .onAppear { nameFocused = true }
    }

    private func save() {
        if let task {
            viewModel.updateTask(task, name: name, arguments: arguments, source: source, destination: destination)
            onSave(task.id)
        } else {
            viewModel.addTask(name: name, arguments: arguments, source: source, destination: destination)
            if let id = viewModel.tasks.last?.id { onSave(id) }
        }
        viewModel.saveTasks()
        onDismiss()
    }
}
