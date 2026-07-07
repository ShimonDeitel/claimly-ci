import Foundation

enum RebateStatus: String, Codable, CaseIterable, Identifiable {
    case notSubmitted
    case submittedAwaitingPayment
    case received
    case expired

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notSubmitted: return "Not Yet Submitted"
        case .submittedAwaitingPayment: return "Submitted - Awaiting Payment"
        case .received: return "Received"
        case .expired: return "Expired / Missed"
        }
    }

    var shortLabel: String {
        switch self {
        case .notSubmitted: return "To Submit"
        case .submittedAwaitingPayment: return "Awaiting"
        case .received: return "Cashed In"
        case .expired: return "Missed"
        }
    }
}

/// Coarse urgency bucket used for both the visual "clock is ticking" ramp and
/// unit-testable business logic (kept independent of SwiftUI Color).
enum UrgencyBucket: String, Equatable {
    case safe        // > 14 days remaining
    case warning     // 4-14 days remaining
    case critical    // 0-3 days remaining (including today)
    case overdue     // deadline already passed, not yet marked expired
    case settled     // received or expired -- no longer ticking

    static func bucket(daysRemaining: Int, status: RebateStatus) -> UrgencyBucket {
        if status == .received || status == .expired { return .settled }
        if daysRemaining < 0 { return .overdue }
        if daysRemaining <= 3 { return .critical }
        if daysRemaining <= 14 { return .warning }
        return .safe
    }
}

struct Rebate: Identifiable, Codable, Equatable {
    var id: UUID
    var storeOrProduct: String
    var amount: Double
    var purchaseDate: Date
    var submissionDeadline: Date
    var status: RebateStatus
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        storeOrProduct: String,
        amount: Double,
        purchaseDate: Date,
        submissionDeadline: Date,
        status: RebateStatus = .notSubmitted,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.storeOrProduct = storeOrProduct
        self.amount = amount
        self.purchaseDate = purchaseDate
        self.submissionDeadline = submissionDeadline
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Whole-day count until the deadline, relative to a supplied "now" for testability.
    func daysRemaining(from now: Date = Date()) -> Int {
        let cal = Calendar.current
        let startOfNow = cal.startOfDay(for: now)
        let startOfDeadline = cal.startOfDay(for: submissionDeadline)
        let comps = cal.dateComponents([.day], from: startOfNow, to: startOfDeadline)
        return comps.day ?? 0
    }

    func urgencyBucket(from now: Date = Date()) -> UrgencyBucket {
        UrgencyBucket.bucket(daysRemaining: daysRemaining(from: now), status: status)
    }

    var isActive: Bool {
        status == .notSubmitted || status == .submittedAwaitingPayment
    }
}
