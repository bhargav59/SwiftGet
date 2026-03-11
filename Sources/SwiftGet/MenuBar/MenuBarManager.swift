import AppKit
import Combine

class MenuBarManager {
    private var statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "SwiftGet")
        }
        
        setupMenu()
        observeDownloads()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Open SwiftGet", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Add URL...", action: #selector(addURL), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Pause All", action: #selector(pauseAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Resume All", action: #selector(resumeAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SwiftGet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem.menu = menu
    }
    
    private func observeDownloads() {
        DownloadManager.shared.$downloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] downloads in
                let active = downloads.filter { $0.status == .downloading }.count
                self?.statusItem.button?.title = active > 0 ? " \(active)" : ""
            }
            .store(in: &cancellables)
    }
    
    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func addURL() {
        NotificationCenter.default.post(name: .showAddDownload, object: nil)
    }
    
    @objc private func pauseAll() {
        DownloadManager.shared.pauseAll()
    }
    
    @objc private func resumeAll() {
        DownloadManager.shared.resumeAll()
    }
}
