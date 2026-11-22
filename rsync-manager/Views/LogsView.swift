import AppKit
import SwiftUI

extension LogEntry {
    var displayStatus: String {
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

    var body: some View {
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
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.tasks.first { $0.id == runningID }?.name ?? "Sync")
                    Text(viewModel.isStopping ? "Stopping…" : "Syncing…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop", systemImage: "stop.fill") { viewModel.stopSync() }
                        .disabled(viewModel.isStopping)
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }
            if filteredLogs.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No history yet" : "No matching runs", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(search.isEmpty ? "Completed runs and their output will appear here." : "Try another search or choose All Profiles.")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(filteredLogs, selection: $selectedLogID) { log in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(taskName(log)).font(.headline).lineLimit(1)
                            RunStatus(status: log.displayStatus).font(.callout)
                            Text(log.timestamp, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(log.id)
                    }.frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                    if let log = selectedLog {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    RunStatus(status: log.displayStatus).font(.headline)
                                    Text(log.timestamp, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Copy Output", systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(log.result, forType: .string)
                                }.labelStyle(.iconOnly).help("Copy complete output")
                            }.padding(16)
                            Divider()
                            LogOutputView(
                                logID: log.id,
                                text: log.result.isEmpty ? "Rsync finished without output." : log.result
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.background)
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
        .onChange(of: search) { _, _ in
            if selectedLog == nil { selectedLogID = filteredLogs.first?.id }
        }
    }
}

/// Keeps a non-wrapping `NSTextView` sized to at least the visible clip area during live resizes.
private final class NonWrappingLogScrollView: NSScrollView {
    private var isUpdatingMinSize = false

    override func layout() {
        super.layout()
        guard !isUpdatingMinSize, let textView = documentView as? NSTextView else { return }
        let contentSize = self.contentSize
        if abs(textView.minSize.width - contentSize.width) > 0.5 ||
           abs(textView.minSize.height - contentSize.height) > 0.5 {
            isUpdatingMinSize = true
            textView.minSize = contentSize
            textView.sizeToFit()
            isUpdatingMinSize = false
        }
    }
}

/// Displays large, non-wrapping sync logs via TextKit 1 `NSTextView` so huge outputs avoid
/// SwiftUI `Text`'s single-layer CoreAnimation backing-store drop.
struct LogOutputView: NSViewRepresentable {
    let logID: UUID
    let text: String

    private static var outputFont: NSFont {
        .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    final class Coordinator {
        var lastLogID: UUID?
        var lastText: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NonWrappingLogScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // TextKit 1 is required so `widthTracksTextView = false` expands `frame.width` horizontally.
        let textView = NSTextView(usingTextLayoutManager: false)
        let font = Self.outputFont
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.font = font
        textView.textColor = .labelColor
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.setAccessibilityIdentifier("logOutputTextView")
        textView.setAccessibilityLabel("Sync output")

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard context.coordinator.lastLogID != logID || context.coordinator.lastText != text else { return }

        context.coordinator.lastLogID = logID
        context.coordinator.lastText = text

        textView.string = text
        textView.font = Self.outputFont
        textView.textColor = .labelColor
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let contentSize = scrollView.contentSize
        if contentSize.width > 0 && contentSize.height > 0 {
            textView.minSize = contentSize
            textView.setFrameSize(contentSize)
        }
        textView.sizeToFit()

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
