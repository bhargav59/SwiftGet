import SwiftUI

@main
struct SwiftGetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(DownloadManager.shared)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add URL...") {
                    NotificationCenter.default.post(name: .showAddDownload, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let showAddDownload = Notification.Name("com.swiftget.showAddDownload")
}
