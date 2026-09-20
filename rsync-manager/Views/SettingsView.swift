import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Rsync Manager") {
                LabeledContent("Sync engine", value: "/usr/bin/rsync")
                Text("Configure folders, behaviour, and exclusions in each profile. Appearance follows your Mac’s settings.")
                    .foregroundStyle(.secondary)
            }
            Section("Help") {
                RsyncGuideLink()
                Button("Open Full Disk Access Settings", systemImage: "lock.shield") { promptFullDiskAccess() }
                Text("If rsync cannot access a protected folder, review the app’s permissions in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 480, height: 320)
    }
}
