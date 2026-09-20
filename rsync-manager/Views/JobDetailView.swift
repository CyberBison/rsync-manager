import SwiftUI

struct RunStatus: View {
    let status: String
    var usesColor = true
    private var title: String {
        switch status {
        case "success": "Completed"
        case "cancelled": "Cancelled"
        case "running": "Syncing"
        default: "Failed"
        }
    }
    private var symbol: String {
        switch status {
        case "success": "checkmark.circle.fill"
        case "cancelled": "stop.circle"
        case "running": "arrow.triangle.2.circlepath"
        default: "exclamationmark.circle.fill"
        }
    }
    private var color: Color {
        status == "success" ? .green : (status == "error" ? .red : .secondary)
    }
    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(usesColor ? color : .primary)
        }
    }
}

struct JobDetailView: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
    let task: SyncTask
    let onEdit: () -> Void
    let onHistory: () -> Void
    private var isRunning: Bool { viewModel.runningTaskID == task.id }
    private var latestLog: LogEntry? { viewModel.logs.last { $0.taskId == task.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SYNC PROFILE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(task.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                    Text("One-way sync from source to destination.").foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        EndpointView(title: "Source", path: task.source).frame(minWidth: 200)
                        Image(systemName: "arrow.right").font(.title2).foregroundStyle(.tertiary)
                            .accessibilityLabel("Syncs to")
                        EndpointView(title: "Destination", path: task.destination).frame(minWidth: 200)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        EndpointView(title: "Source", path: task.source)
                        Label("Syncs to", systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary)
                        EndpointView(title: "Destination", path: task.destination)
                    }
                }
                .padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

                if isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(viewModel.isStopping ? "Stopping sync…" : "Sync in progress").font(.headline)
                            Spacer()
                            if let date = viewModel.runStartedAt {
                                Text(date, style: .timer).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Text("Rsync is transferring files. Output will be available in History when the run finishes.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Stop Sync", systemImage: "stop.fill") { viewModel.stopSync() }
                            .buttonStyle(.glass).disabled(viewModel.isStopping)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Behaviour").font(.title3.weight(.semibold))
                        Spacer()
                        Button("Edit Profile", systemImage: "pencil", action: onEdit)
                            .buttonStyle(.glass).disabled(isRunning)
                    }
                    Label("Source files are copied to the destination", systemImage: "arrow.right.doc.on.clipboard")
                    if task.arguments.contains("--delete") {
                        Label {
                            Text("Files absent from the source may be deleted at the destination")
                        } icon: {
                            Image(systemName: "trash").foregroundStyle(.orange)
                        }
                    }
                    if task.arguments.contains("--dry-run") || task.arguments.split(separator: " ").contains("-n") {
                        Label("Dry run — previews changes without copying files", systemImage: "eye")
                    }
                    Text("Custom flags and exclusions are available in Profile Options.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Latest activity").font(.title3.weight(.semibold))
                        Spacer()
                        Button("View History", systemImage: "clock.arrow.circlepath", action: onHistory)
                            .buttonStyle(.borderless)
                    }
                    if let date = task.lastSyncDate {
                        HStack {
                            RunStatus(status: task.lastSyncStatus ?? "error")
                            Spacer()
                            Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                        }
                        if let log = latestLog {
                            Text(log.result.isEmpty ? "Rsync finished without output." : log.result)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                        }
                    } else {
                        Label("No runs yet", systemImage: "clock").foregroundStyle(.secondary)
                        Text("Run this profile to see its result here.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct EndpointView: View {
    let title: String
    let path: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: path.contains(":") ? "network" : "folder")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(endpointName(path)).font(.title3.weight(.semibold)).lineLimit(2)
            Text(path).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileInspector: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
    let task: SyncTask
    let onEdit: () -> Void
    var body: some View {
        Form {
            Section("Profile Options") {
                LabeledContent("Direction", value: "One-way")
                LabeledContent("Executable", value: "/usr/bin/rsync")
            }
            Section("Rsync arguments") {
                Text(task.arguments.isEmpty ? "No additional arguments" : task.arguments)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("Includes behaviour flags, exclusions, and advanced options exactly as saved.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Edit Arguments…", action: onEdit).disabled(viewModel.runningTaskID == task.id)
            }
            Section("Last run") {
                if let date = task.lastSyncDate {
                    Text(date, format: .dateTime)
                    RunStatus(status: task.lastSyncStatus ?? "error")
                } else {
                    Text("Not run yet").foregroundStyle(.secondary)
                }
            }
            Section {
                RsyncGuideLink()
            }
        }
        .formStyle(.grouped)
    }
}

struct RsyncGuideLink: View {
    var body: some View {
        Link(destination: URL(string: "https://github.com/cyberbison/rsync-manager/blob/main/rsync_help_guide.md")!) {
            Label("Rsync Argument Guide", systemImage: "book")
        }
    }
}
