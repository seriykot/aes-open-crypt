import AESOpenCore
import SwiftUI

@main
struct AESOpenCryptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = BatchModel.shared

    var body: some Scene {
        Window("AES Open Crypt", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") {
                    openFiles()
                }
                .keyboardShortcut("o")
            }
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.add(urls: panel.urls, preferredMode: nil)
        }
    }
}
