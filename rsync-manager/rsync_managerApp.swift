//
//  rsync_managerApp.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import AppKit
import SwiftUI

@main
struct rsync_managerApp: App {
    init() {
            //promptFullDiskAccess()
        }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

func promptFullDiskAccess() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    NSWorkspace.shared.open(url)
}
    