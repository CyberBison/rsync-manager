import AppKit
import SwiftUI

@main
struct rsync_managerApp: App {
    @StateObject private var viewModel: SyncTaskViewModel

    init() {
        #if DEBUG
        let testDirectory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            ? ProcessInfo.processInfo.environment["RSYNC_TEST_DIRECTORY"].map { URL(fileURLWithPath: $0) } : nil
        _viewModel = StateObject(wrappedValue: SyncTaskViewModel(storageDirectory: testDirectory))
        #else
        _viewModel = StateObject(wrappedValue: SyncTaskViewModel())
        #endif
    }

    private var testAppearance: ColorScheme? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return nil }
        return ProcessInfo.processInfo.arguments.contains("-dark") ? .dark : .light
        #else
        return nil
        #endif
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(viewModel).preferredColorScheme(testAppearance)
        }
        .defaultSize(width: 1080, height: 740)
        .commands { ProfileCommands() }
        Settings { SettingsView().preferredColorScheme(testAppearance) }
    }
}

struct ProfileCommands: Commands {
    @FocusedValue(\.newSyncProfile) private var newProfile
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Sync Profile…") { newProfile?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(newProfile == nil)
        }
    }
}

func promptFullDiskAccess() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    NSWorkspace.shared.open(url)
}
