import SwiftUI

struct MainListView: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
    @Binding var selection: UUID?
    let onAdd: () -> Void
    let onEdit: (SyncTask) -> Void
    let onDelete: (SyncTask) -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Profiles") {
                ForEach(viewModel.tasks) { task in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.name).font(.headline).lineLimit(1)
                            Text("\(endpointName(task.source)) → \(endpointName(task.destination))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if viewModel.runningTaskID == task.id {
                                Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if let status = task.lastSyncStatus {
                                RunStatus(status: status, usesColor: selection != task.id).font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(task.id)
                    .contextMenu {
                        Button("Run Sync", systemImage: "play") { viewModel.runSync(task: task) }
                            .disabled(viewModel.runningTaskID != nil)
                        Button("Edit Profile…", systemImage: "pencil") { onEdit(task) }
                            .disabled(viewModel.runningTaskID == task.id)
                        Divider()
                        Button("Delete Profile…", systemImage: "trash", role: .destructive) { onDelete(task) }
                            .disabled(viewModel.runningTaskID == task.id)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Profiles")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("New Profile", systemImage: "plus", action: onAdd)
                    .buttonStyle(.borderless)
                Spacer()
                Text("\(viewModel.tasks.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .padding()
        }
    }
}

func endpointName(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    return name.isEmpty ? path : name
}
