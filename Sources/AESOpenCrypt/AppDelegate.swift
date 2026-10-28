import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider.shared
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.open(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    @objc func encryptSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        handle(pasteboard, mode: .encrypt)
    }

    @objc func decryptSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        handle(pasteboard, mode: .decrypt)
    }

    private func handle(_ pasteboard: NSPasteboard, mode: AppModel.Mode) {
        MainActor.assumeIsolated {
            guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let first = items.first else {
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            AppModel.shared.open(url: first, preferredMode: mode)
        }
    }
}
