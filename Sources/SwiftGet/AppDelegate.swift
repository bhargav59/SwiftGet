import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var menuBarManager: MenuBarManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupNotifications()
        menuBarManager = MenuBarManager()
        NativeMessagingBridge.shared.start()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        DownloadManager.shared.pauseAll()
    }
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                print("Notifications authorized")
            }
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "swiftget" {
                handleSwiftGetURL(url)
            }
        }
    }
    
    private func handleSwiftGetURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let downloadURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: downloadURL) else { return }
        DownloadManager.shared.addDownload(url: url)
    }
}
