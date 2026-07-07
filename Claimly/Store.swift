import Foundation
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published private(set) var rebates: [Rebate] = []

    static let freeLimit = 5

    private let fileURL: URL
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("claimly_rebates.json")

        // Mandatory UI-test reset hook: wipe persisted state before loading so every
        // UI test run starts from a clean slate rather than accumulating entries
        // across CI re-runs of the same simulator/app install.
        if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
            try? FileManager.default.removeItem(at: fileURL)
        }

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            rebates = []
            return
        }
        rebates = (try? JSONDecoder().decode([Rebate].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rebates) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - CRUD

    @discardableResult
    func addRebate(
        storeOrProduct: String,
        amount: Double,
        purchaseDate: Date,
        submissionDeadline: Date,
        notes: String = ""
    ) -> Rebate {
        let rebate = Rebate(
            storeOrProduct: storeOrProduct,
            amount: amount,
            purchaseDate: purchaseDate,
            submissionDeadline: submissionDeadline,
            notes: notes
        )
        rebates.append(rebate)
        save()
        scheduleNotification(for: rebate)
        return rebate
    }

    func updateRebate(_ rebate: Rebate) {
        guard let idx = rebates.firstIndex(where: { $0.id == rebate.id }) else { return }
        rebates[idx] = rebate
        save()
        cancelNotification(for: rebate)
        scheduleNotification(for: rebate)
    }

    func deleteRebate(_ rebate: Rebate) {
        rebates.removeAll { $0.id == rebate.id }
        save()
        cancelNotification(for: rebate)
    }

    func setStatus(_ status: RebateStatus, for rebate: Rebate) {
        guard var updated = rebates.first(where: { $0.id == rebate.id }) else { return }
        updated.status = status
        updateRebate(updated)
    }

    // MARK: - Free tier

    var canAddMoreFree: Bool {
        rebates.count < Store.freeLimit
    }

    // MARK: - Tallies (unit-testable business logic)

    /// Total dollar amount of rebates marked Received in the current calendar year.
    func totalReclaimedThisYear(referenceDate: Date = Date()) -> Double {
        let year = Calendar.current.component(.year, from: referenceDate)
        return rebates
            .filter { $0.status == .received && Calendar.current.component(.year, from: $0.createdAt) == year }
            .reduce(0) { $0 + $1.amount }
    }

    /// Sum of amounts for active (not yet submitted / awaiting payment) rebates
    /// whose deadline is within `withinDays` days -- the Pro-only "at risk" stat.
    func totalAtRiskOfExpiring(withinDays: Int = 14, referenceDate: Date = Date()) -> Double {
        rebates
            .filter { $0.isActive && $0.daysRemaining(from: referenceDate) <= withinDays }
            .reduce(0) { $0 + $1.amount }
    }

    func rebatesGrouped(referenceDate: Date = Date()) -> [UrgencyBucket: [Rebate]] {
        Dictionary(grouping: rebates) { $0.urgencyBucket(from: referenceDate) }
    }

    // MARK: - Notifications

    private let notificationLeadTimeKey = "claimly_notification_lead_days"
    private let notificationsEnabledKey = "claimly_notifications_enabled"

    var notificationLeadDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: notificationLeadTimeKey)
            return stored == 0 ? 3 : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationLeadTimeKey)
            rescheduleAllNotifications()
        }
    }

    var notificationsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: notificationsEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey)
            if newValue {
                rescheduleAllNotifications()
            } else {
                notificationCenter.removeAllPendingNotificationRequests()
            }
        }
    }

    func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func rescheduleAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        guard notificationsEnabled else { return }
        for rebate in rebates where rebate.isActive {
            scheduleNotification(for: rebate)
        }
    }

    private func scheduleNotification(for rebate: Rebate) {
        guard notificationsEnabled, rebate.isActive else { return }
        let cal = Calendar.current
        guard let fireDate = cal.date(byAdding: .day, value: -notificationLeadDays, to: rebate.submissionDeadline),
              fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rebate Deadline Approaching"
        content.body = "\(rebate.storeOrProduct) ($\(String(format: "%.2f", rebate.amount))) is due in \(notificationLeadDays) day(s)."
        content.sound = .default

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: rebate.id.uuidString, content: content, trigger: trigger)
        notificationCenter.add(request)
    }

    private func cancelNotification(for rebate: Rebate) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [rebate.id.uuidString])
    }
}
