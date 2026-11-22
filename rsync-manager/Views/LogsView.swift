import AppKit
import SwiftUI

extension LogEntry {
    var displayStatus: String {
        if let status { return status }
        if result.hasPrefix("Sync cancelled by user.") { return "cancelled" }
        return success && !result.contains("rsync error") ? "success" : "error"
    }
}

struct LogsView: View {
    @EnvironmentObject private var viewModel: SyncTaskViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTaskID: UUID?
    @State private var selectedLogID: UUID?
    @State private var search = ""

    init(initialTaskID: UUID? = nil) {
        _selectedTaskID = State(initialValue: initialTaskID)
    }

    private var filteredLogs: [LogEntry] {
        viewModel.logs.reversed().filter {
            (selectedTaskID == nil || $0.taskId == selectedTaskID) &&
            (search.isEmpty || $0.result.localizedCaseInsensitiveContains(search) || taskName($0).localizedCaseInsensitiveContains(search))
        }
    }
    private var selectedLog: LogEntry? { filteredLogs.first { $0.id == selectedLogID } }
    private func taskName(_ log: LogEntry) -> String {
        viewModel.tasks.first { $0.id == log.taskId }?.name ?? "Deleted profile"
    }
    private func isRunningLog(_ log: LogEntry) -> Bool {
        log.id == viewModel.activeLogID || (log.displayStatus == "running" && viewModel.runningTaskID == log.taskId)
    }

    var body: some View {
        let logs = filteredLogs
        VStack(spacing: 0) {
            HStack {
                Text("Sync History").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.glass)
            }.padding(20)
            HStack {
                Picker("Profile", selection: $selectedTaskID) {
                    Text("All Profiles").tag(UUID?.none)
                    ForEach(viewModel.tasks) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 300)
                Spacer()
                TextField("Search output", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
            }.padding(.horizontal, 20).padding(.bottom, 16)
            if let runningID = viewModel.runningTaskID,
               selectedTaskID == nil || selectedTaskID == runningID {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(viewModel.tasks.first { $0.id == runningID }?.name ?? "Sync")
                        Text(viewModel.isStopping ? "Stopping…" : "Syncing…").foregroundStyle(.secondary)
                        if let pct = viewModel.syncProgressPercentage {
                            Text("\(pct)%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Stop", systemImage: "stop.fill") { viewModel.stopSync() }
                            .disabled(viewModel.isStopping)
                    }
                    if let progress = viewModel.syncProgress {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }
            if logs.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No history yet" : "No matching runs", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(search.isEmpty ? "Completed runs and their output will appear here." : "Try another search or choose All Profiles.")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(logs, selection: $selectedLogID) { log in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(taskName(log)).font(.headline).lineLimit(1)
                            RunStatus(status: log.displayStatus,
                                      progressPercentage: isRunningLog(log) ? viewModel.syncProgressPercentage : nil)
                                .font(.callout)
                            Text(log.timestamp, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(log.id)
                    }.frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                    if let log = logs.first(where: { $0.id == selectedLogID }) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    RunStatus(status: log.displayStatus,
                                              progressPercentage: isRunningLog(log) ? viewModel.syncProgressPercentage : nil)
                                        .font(.headline)
                                    Text(log.timestamp, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Copy Output", systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(log.result, forType: .string)
                                }.labelStyle(.iconOnly).help("Copy complete output")
                            }.padding(16)
                            Divider()
                            RunOutputView(output: log.result)
                                .id(log.id)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.background)
                                .overlay(alignment: .topLeading) {
                                    if log.result.isEmpty {
                                        Text(isRunningLog(log) ? "Waiting for rsync output…" : "Rsync finished without output.")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(16)
                                    }
                                }
                        }.frame(minWidth: 340)
                    } else {
                        ContentUnavailableView("Select a run", systemImage: "text.alignleft", description: Text("Inspect its full rsync output here."))
                            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 500, idealHeight: 620)
        .onAppear { selectedLogID = filteredLogs.first?.id }
        .onChange(of: selectedTaskID) { _, _ in selectedLogID = filteredLogs.first?.id }
        .onChange(of: viewModel.logs.last?.id) { oldLastID, newLastID in
            if selectedLogID == nil || selectedLogID == oldLastID {
                selectedLogID = filteredLogs.first?.id ?? newLastID
            }
        }
        .onChange(of: search) { _, _ in
            if selectedLog == nil { selectedLogID = filteredLogs.first?.id }
        }
    }
}

struct RunOutputView: NSViewRepresentable {
    let output: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            let unboundedSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isEditable = false
            textView.isRichText = false
            textView.drawsBackground = false
            textView.isHorizontallyResizable = true
            textView.maxSize = unboundedSize
            textView.autoresizingMask = []
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = unboundedSize
            textView.textContainerInset = NSSize(width: 11, height: 16)
            textView.setAccessibilityIdentifier("Run output")
        }
        return scrollView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = textView.textStorage else { return }
        let previous = context.coordinator.output
        guard previous != output else { return }
        context.coordinator.output = output

        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        if output.hasPrefix(previous) {
            let appended = String(output.dropFirst(previous.count))
            textStorage.append(NSAttributedString(string: appended, attributes: attributes))
        } else {
            textStorage.setAttributedString(NSAttributedString(string: output, attributes: attributes))
        }
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    final class Coordinator {
        var output = ""
    }
}
