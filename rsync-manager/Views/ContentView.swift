import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
    @State private var selection: UUID?
    @State private var presentation: ProfilePresentation?
    @State private var deletingTask: SyncTask?
    @State private var showingInspector = false
    @State private var availableSize = CGSize(width: 1080, height: 740)

    private var selectedTask: SyncTask? {
        viewModel.tasks.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            MainListView(selection: $selection, onAdd: { presentation = .create },
                         onEdit: { presentation = .edit($0) }, onDelete: { deletingTask = $0 })
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            Group {
                if let task = selectedTask {
                    JobDetailView(task: task, onEdit: { presentation = .edit(task) },
                                  onHistory: { presentation = .history(selection) })
                } else {
                    ContentUnavailableView {
                        Label(viewModel.tasks.isEmpty ? "Your next sync starts here" : "Select a profile",
                              systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text(viewModel.tasks.isEmpty
                             ? "Create a profile to keep a folder backed up or copy files to another destination."
                             : "Choose a profile in the sidebar to see its folders and recent activity.")
                    } actions: {
                        Button("New Profile", systemImage: "plus") { presentation = .create }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(selectedTask?.name ?? "Rsync Manager")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let task = selectedTask {
                        if viewModel.runningTaskID == task.id {
                            Button("Stop Sync", systemImage: "stop.fill") { viewModel.stopSync() }
                                .disabled(viewModel.isStopping)
                        } else {
                            Button("Run Sync", systemImage: "play.fill") { viewModel.runSync(task: task) }
                                .disabled(viewModel.runningTaskID != nil)
                                .keyboardShortcut("r", modifiers: .command)
                        }
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button("History", systemImage: "clock.arrow.circlepath") { presentation = .history(selection) }
                        .keyboardShortcut("h", modifiers: [.command, .shift])
                    Button("Profile Options", systemImage: "sidebar.right") { toggleInspector() }
                        .disabled(selectedTask == nil)
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showingInspector) {
            if let task = selectedTask {
                ProfileInspector(task: task, onEdit: { presentation = .edit(task) })
                    .inspectorColumnWidth(290)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            availableSize = size
            if size.width < 1000 && showingInspector {
                showingInspector = false
                if let task = selectedTask { presentation = .options(task) }
            }
        }
        .sheet(item: $presentation) { item in
            switch item {
            case .create:
                FormView(height: editorHeight, onDismiss: { presentation = nil }, onSave: { selection = $0 })
            case .edit(let task):
                FormView(task: task, height: editorHeight, onDismiss: { presentation = nil }, onSave: { selection = $0 })
            case .options(let task):
                VStack(spacing: 0) {
                    HStack {
                        Text("Profile Options").font(.title2.weight(.semibold))
                        Spacer()
                        Button("Done") { presentation = nil }.keyboardShortcut(.cancelAction)
                    }.padding(20)
                    ProfileInspector(task: task, onEdit: { presentation = .edit(task) })
                }
                .frame(width: 380, height: min(520, editorHeight))
            case .history(let taskID):
                LogsView(initialTaskID: taskID)
            }
        }
        .confirmationDialog("Delete profile?", isPresented: Binding(
            get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) {
                guard let task = deletingTask else { return }
                viewModel.tasks.removeAll { $0.id == task.id }
                if selection == task.id { selection = viewModel.tasks.first?.id }
                deletingTask = nil
            }
        } message: {
            Text("“\(deletingTask?.name ?? "")” will be removed. Its folders, files, and run history will be kept.")
        }
        .onAppear {
            selection = selection ?? viewModel.tasks.first?.id
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                DispatchQueue.main.async {
                    let narrow = ProcessInfo.processInfo.arguments.contains("-narrow")
                    NSApp.keyWindow?.setContentSize(NSSize(width: narrow ? 760 : 1280, height: narrow ? 600 : 820))
                }
            }
            #endif
        }
        .onChange(of: selection) { _, id in
            if id == nil { showingInspector = false }
        }
        .onChange(of: viewModel.tasks) { _, _ in viewModel.saveTasks() }
        .focusedSceneValue(\.newSyncProfile, { presentation = .create })
    }

    private var editorHeight: CGFloat { min(620, max(440, availableSize.height - 70)) }

    private func toggleInspector() {
        if availableSize.width < 1000, let task = selectedTask {
            presentation = .options(task)
        } else {
            showingInspector.toggle()
        }
    }

}

private struct NewSyncProfileKey: FocusedValueKey {
    typealias Value = () -> Void
}
extension FocusedValues {
    var newSyncProfile: (() -> Void)? {
        get { self[NewSyncProfileKey.self] }
        set { self[NewSyncProfileKey.self] = newValue }
    }
}

private enum ProfilePresentation: Identifiable {
    case create
    case edit(SyncTask)
    case options(SyncTask)
    case history(UUID?)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let task): "edit-\(task.id)"
        case .options(let task): "options-\(task.id)"
        case .history: "history"
        }
    }
}
