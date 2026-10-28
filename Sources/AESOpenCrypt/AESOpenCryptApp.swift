import SwiftUI

@main
struct AESOpenCryptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("AES Open Crypt") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File…") {
                    openFile()
                }
                .keyboardShortcut("o")
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.open(url: url, preferredMode: nil)
        }
    }
}
