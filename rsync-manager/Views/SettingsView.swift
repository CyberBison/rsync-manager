//
//  SettingsView.swift
//  rsync-manager
//
//  Created by CyberBison on 23.01.2025.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.largeTitle)
            Text("Configure your preferences here.")
            Spacer()
        }
        .padding()
        .navigationTitle("Settings")
    }
}
