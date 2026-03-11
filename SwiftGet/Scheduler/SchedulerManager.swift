import Foundation
import AppKit
import Combine

/// Manages scheduled download windows and bandwidth throttling.
@MainActor
final class SchedulerManager: ObservableObject {

    static let shared = SchedulerManager()

    // MARK: - Scheduled Window

    @Published var schedulingEnabled: Bool = false
    @Published var scheduleStartHour: Int = 2    // 2 AM
    @Published var scheduleStartMinute: Int = 0
    @Published var scheduleEndHour: Int = 6      // 6 AM
    @Published var scheduleEndMinute: Int = 0

    @Published var bandwidthLimitEnabled: Bool = false
    @Published var bandwidthLimitBytesPerSecond: Double = 1_048_576  // 1 MB/s default

    @Published var shutdownAfterQueueCompletion: Bool = false

    // MARK: - Private

    private var timer: Timer?
    private var wasInWindow: Bool = false

    // MARK: - Init

    private init() {
        loadSettings()
        startTimer()
    }

    // MARK: - Public

    func resumePending() {
        if schedulingEnabled && isInScheduleWindow() {
            DownloadManager.shared.resumeAll()
        } else if !schedulingEnabled {
            DownloadManager.shared.resumeAll()
        }
    }

    func isInScheduleWindow() -> Bool {
        guard schedulingEnabled else { return true }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = scheduleStartHour * 60 + scheduleStartMinute
        let endMinutes = scheduleEndHour * 60 + scheduleEndMinute

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Crosses midnight
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }

    var effectiveBandwidthLimit: Double {
        if bandwidthLimitEnabled { return bandwidthLimitBytesPerSecond }
        return 0
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard schedulingEnabled else { return }
        let inWindow = isInScheduleWindow()

        if inWindow && !wasInWindow {
            // Window opened — resume downloads
            DownloadManager.shared.resumeAll()
        } else if !inWindow && wasInWindow {
            // Window closed — pause downloads
            DownloadManager.shared.pauseAll()
        }
        wasInWindow = inWindow

        // Shutdown check
        if shutdownAfterQueueCompletion {
            let allDone = DownloadManager.shared.tasks.allSatisfy { $0.status.isTerminal }
            if allDone && !DownloadManager.shared.tasks.isEmpty {
                scheduleShutdown()
            }
        }
    }

    // MARK: - Shutdown

    private func scheduleShutdown() {
        let alert = NSAlert()
        alert.messageText = "Queue Complete — Shutting Down"
        alert.informativeText = "All downloads finished. Your Mac will shut down in 60 seconds."
        alert.addButton(withTitle: "Cancel Shutdown")
        alert.addButton(withTitle: "Shut Down Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            shutdownAfterQueueCompletion = false
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/shutdown")
            process.arguments = ["-h", "now"]
            try? process.run()
        }
    }

    // MARK: - Persistence

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let schedulingEnabled = "schedulingEnabled"
        static let startHour = "scheduleStartHour"
        static let startMinute = "scheduleStartMinute"
        static let endHour = "scheduleEndHour"
        static let endMinute = "scheduleEndMinute"
        static let bwEnabled = "bandwidthLimitEnabled"
        static let bwLimit = "bandwidthLimitBytesPerSecond"
        static let shutdown = "shutdownAfterQueueCompletion"
    }

    func saveSettings() {
        defaults.set(schedulingEnabled, forKey: Keys.schedulingEnabled)
        defaults.set(scheduleStartHour, forKey: Keys.startHour)
        defaults.set(scheduleStartMinute, forKey: Keys.startMinute)
        defaults.set(scheduleEndHour, forKey: Keys.endHour)
        defaults.set(scheduleEndMinute, forKey: Keys.endMinute)
        defaults.set(bandwidthLimitEnabled, forKey: Keys.bwEnabled)
        defaults.set(bandwidthLimitBytesPerSecond, forKey: Keys.bwLimit)
        defaults.set(shutdownAfterQueueCompletion, forKey: Keys.shutdown)
    }

    private func loadSettings() {
        if defaults.object(forKey: Keys.schedulingEnabled) != nil {
            schedulingEnabled = defaults.bool(forKey: Keys.schedulingEnabled)
        }
        if defaults.object(forKey: Keys.startHour) != nil {
            scheduleStartHour = defaults.integer(forKey: Keys.startHour)
        }
        if defaults.object(forKey: Keys.startMinute) != nil {
            scheduleStartMinute = defaults.integer(forKey: Keys.startMinute)
        }
        if defaults.object(forKey: Keys.endHour) != nil {
            scheduleEndHour = defaults.integer(forKey: Keys.endHour)
        }
        if defaults.object(forKey: Keys.endMinute) != nil {
            scheduleEndMinute = defaults.integer(forKey: Keys.endMinute)
        }
        if defaults.object(forKey: Keys.bwEnabled) != nil {
            bandwidthLimitEnabled = defaults.bool(forKey: Keys.bwEnabled)
        }
        if defaults.object(forKey: Keys.bwLimit) != nil {
            bandwidthLimitBytesPerSecond = defaults.double(forKey: Keys.bwLimit)
        }
        if defaults.object(forKey: Keys.shutdown) != nil {
            shutdownAfterQueueCompletion = defaults.bool(forKey: Keys.shutdown)
        }
    }
}

