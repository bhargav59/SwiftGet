import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureNotifications()
        configureURLScheme()
        NativeMessagingServer.shared.start()
        SchedulerManager.shared.resumePending()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DownloadManager.shared.pauseAllOnQuit()
        NativeMessagingServer.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in Menu Bar when main window is closed
        return false
    }

    // MARK: - URL Scheme (swiftget://)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "swiftget" else { continue }
            handleSwiftGetURL(url)
        }
    }

    private func handleSwiftGetURL(_ url: URL) {
        // swiftget://add?url=<encoded-url>&filename=<name>&referrer=<ref>
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "add",
              let downloadURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let downloadURL = URL(string: downloadURLString) else {
            return
        }
        let filename = components.queryItems?.first(where: { $0.name == "filename" })?.value
        let referrer = components.queryItems?.first(where: { $0.name == "referrer" })?.value
        let cookies = components.queryItems?.first(where: { $0.name == "cookies" })?.value

        let task = DownloadTask(
            url: downloadURL,
            suggestedFilename: filename,
            referrer: referrer,
            cookies: cookies
        )
        DownloadManager.shared.enqueue(task)

        // Bring app to foreground
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Notifications

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[SwiftGet] Notification permission error: \(error)")
            }
        }

        // Observe internal download events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadCompleted(_:)),
            name: .downloadCompleted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadFailed(_:)),
            name: .downloadFailed,
            object: nil
        )
    }

    @MainActor @objc private func handleDownloadCompleted(_ note: Notification) {
        guard let task = note.object as? DownloadTask else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = task.displayName
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "complete-\(task.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor @objc private func handleDownloadFailed(_ note: Notification) {
        guard let task = note.object as? DownloadTask else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download Failed"
        content.body = task.displayName
        content.sound = .defaultCritical
        let request = UNNotificationRequest(
            identifier: "failed-\(task.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - URL Scheme Registration

    private func configureURLScheme() {
        // swiftget:// is declared in Info.plist CFBundleURLTypes
        // Nothing to do programmatically; handler is application(_:open:)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        completionHandler()
    }
}
