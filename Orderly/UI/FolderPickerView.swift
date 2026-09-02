//
//  FolderPickerView.swift
//  Orderly
//

import SwiftUI
import AppKit

struct FolderPickerView: View {

    let onFolderSelected: (URL) -> Void

    var body: some View {
        Button("Choose Folder") {
            chooseFolder()
        }
        .buttonStyle(.borderedProminent)
    }

    private func chooseFolder() {

        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        panel.prompt = "Choose"

        if panel.runModal() == .OK,
           let url = panel.url {

            onFolderSelected(url)
        }
    }
}
