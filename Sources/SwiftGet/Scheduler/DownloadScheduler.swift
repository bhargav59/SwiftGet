import Foundation

class DownloadScheduler {
    static let shared = DownloadScheduler()
    
    private var timer: Timer?
    private var scheduledItems: [UUID: Date] = [:]
    
    private init() {
        startScheduler()
    }
    
    func schedule(item: DownloadItem, at date: Date) {
        item.scheduledTime = date
        scheduledItems[item.id] = date
    }
    
    private func startScheduler() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkScheduledDownloads()
        }
    }
    
    private func checkScheduledDownloads() {
        let now = Date()
        for (id, scheduledTime) in scheduledItems {
            if now >= scheduledTime {
                if let item = DownloadManager.shared.downloads.first(where: { $0.id == id }) {
                    DownloadManager.shared.resumeDownload(item)
                    scheduledItems.removeValue(forKey: id)
                }
            }
        }
    }
    
    func setGlobalSchedule(startTime: DateComponents, endTime: DateComponents) {
        // Store schedule preferences
        UserDefaults.standard.set(startTime.hour, forKey: "scheduleStartHour")
        UserDefaults.standard.set(startTime.minute, forKey: "scheduleStartMinute")
        UserDefaults.standard.set(endTime.hour, forKey: "scheduleEndHour")
        UserDefaults.standard.set(endTime.minute, forKey: "scheduleEndMinute")
    }
    
    func isWithinScheduledWindow() -> Bool {
        guard let startHour = UserDefaults.standard.object(forKey: "scheduleStartHour") as? Int,
              let endHour = UserDefaults.standard.object(forKey: "scheduleEndHour") as? Int else {
            return true // No schedule = always allowed
        }
        
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = startHour * 60 + (UserDefaults.standard.integer(forKey: "scheduleStartMinute"))
        let endMinutes = endHour * 60 + (UserDefaults.standard.integer(forKey: "scheduleEndMinute"))
        
        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            // Overnight schedule
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }
    }
}
