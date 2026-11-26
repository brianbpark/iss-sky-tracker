import UserNotifications

/// Schedules a local reminder shortly before a visible pass.
enum NotificationService {
    static let leadTime: TimeInterval = 10 * 60

    static func identifier(for pass: ISSPass) -> String {
        "iss-pass-\(Int(pass.rise.date.timeIntervalSince1970))"
    }

    static func isScheduled(_ pass: ISSPass) async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier(for: pass) }
    }

    /// Returns false if the user declined notifications or the pass is too soon.
    static func schedule(_ pass: ISSPass) async -> Bool {
        guard let start = pass.visibleStart else { return false }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }

        let fireDate = start.date.addingTimeInterval(-leadTime)
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 1 else { return false }

        let content = UNMutableNotificationContent()
        content.title = "ISS visible in 10 minutes"
        let time = start.date.formatted(date: .omitted, time: .shortened)
        let peak = Int((pass.maxVisibleElevation ?? pass.culmination.elevation).rounded())
        content.body = "Look \(start.compass) at \(time). It climbs to \(peak)° and disappears to the \(pass.visibleEnd?.compass ?? pass.setting.compass)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier(for: pass), content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        do { try await center.add(request); return true } catch { return false }
    }

    static func cancel(_ pass: ISSPass) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: pass)])
    }
}
