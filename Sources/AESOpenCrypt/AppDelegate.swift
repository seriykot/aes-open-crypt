import AESOpenCore
import AESCryptKit
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider.shared
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow else { return }
                self.configure(window)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
                self.configure(window)
                self.applyInitialWindowSizeIfNeeded(window)
            }
            CLIInstaller.ensureInstalled()
        }
    }

    private func configure(_ window: NSWindow) {
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    private func applyInitialWindowSizeIfNeeded(_ window: NSWindow) {
        let key = "didApplyInitialWindowSize"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        window.setContentSize(NSSize(width: 600, height: 660))
        window.center()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        BatchModel.shared.add(urls: urls, preferredMode: nil)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
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

    private func handle(_ pasteboard: NSPasteboard, mode: AESCryptBatchMode) {
        MainActor.assumeIsolated {
            guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  !items.isEmpty else {
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            BatchModel.shared.add(urls: items, preferredMode: mode)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
