import XCTest
@testable import Claimly

@MainActor
final class ClaimlyTests: XCTestCase {

    var store: Store!

    override func setUpWithError() throws {
        store = Store()
        // Ensure a clean slate for every test regardless of prior persisted state.
        for r in store.rebates {
            store.deleteRebate(r)
        }
    }

    override func tearDownWithError() throws {
        for r in store.rebates {
            store.deleteRebate(r)
        }
        store = nil
    }

    // MARK: - Urgency bucket logic

    func testUrgencyBucketSafeWhenFarOut() {
        let bucket = UrgencyBucket.bucket(daysRemaining: 30, status: .notSubmitted)
        XCTAssertEqual(bucket, .safe)
    }

    func testUrgencyBucketWarningBetween4And14Days() {
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: 14, status: .notSubmitted), .warning)
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: 4, status: .notSubmitted), .warning)
    }

    func testUrgencyBucketCriticalWithin3Days() {
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: 3, status: .notSubmitted), .critical)
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: 0, status: .notSubmitted), .critical)
    }

    func testUrgencyBucketOverdueWhenNegativeDays() {
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: -1, status: .notSubmitted), .overdue)
    }

    func testUrgencyBucketSettledWhenReceivedOrExpiredRegardlessOfDays() {
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: -5, status: .received), .settled)
        XCTAssertEqual(UrgencyBucket.bucket(daysRemaining: 1, status: .expired), .settled)
    }

    func testDaysRemainingCalculation() {
        let now = Date()
        let deadline = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        let rebate = Rebate(storeOrProduct: "Test", amount: 10, purchaseDate: now, submissionDeadline: deadline)
        XCTAssertEqual(rebate.daysRemaining(from: now), 10)
    }

    // MARK: - Store CRUD

    func testAddRebateAppendsToStore() {
        store.addRebate(storeOrProduct: "Best Buy TV", amount: 25, purchaseDate: Date(), submissionDeadline: Date())
        XCTAssertEqual(store.rebates.count, 1)
        XCTAssertEqual(store.rebates.first?.storeOrProduct, "Best Buy TV")
    }

    func testDeleteRebateRemovesIt() {
        let rebate = store.addRebate(storeOrProduct: "Delete Me", amount: 5, purchaseDate: Date(), submissionDeadline: Date())
        store.deleteRebate(rebate)
        XCTAssertTrue(store.rebates.isEmpty)
    }

    func testUpdateRebateChangesFields() {
        let rebate = store.addRebate(storeOrProduct: "Old Name", amount: 5, purchaseDate: Date(), submissionDeadline: Date())
        var updated = rebate
        updated.storeOrProduct = "New Name"
        updated.amount = 15
        store.updateRebate(updated)
        XCTAssertEqual(store.rebates.first?.storeOrProduct, "New Name")
        XCTAssertEqual(store.rebates.first?.amount, 15)
    }

    func testSetStatusToReceivedUpdatesRebate() {
        let rebate = store.addRebate(storeOrProduct: "Item", amount: 10, purchaseDate: Date(), submissionDeadline: Date())
        store.setStatus(.received, for: rebate)
        XCTAssertEqual(store.rebates.first?.status, .received)
    }

    // MARK: - Free tier limit

    func testCanAddMoreFreeUnderLimit() {
        for i in 0..<(Store.freeLimit - 1) {
            store.addRebate(storeOrProduct: "Item \(i)", amount: 1, purchaseDate: Date(), submissionDeadline: Date())
        }
        XCTAssertTrue(store.canAddMoreFree)
    }

    func testCanAddMoreFreeFalseAtLimit() {
        for i in 0..<Store.freeLimit {
            store.addRebate(storeOrProduct: "Item \(i)", amount: 1, purchaseDate: Date(), submissionDeadline: Date())
        }
        XCTAssertFalse(store.canAddMoreFree)
    }

    // MARK: - Total reclaimed tally

    func testTotalReclaimedThisYearSumsOnlyReceived() {
        let now = Date()
        let r1 = store.addRebate(storeOrProduct: "A", amount: 20, purchaseDate: now, submissionDeadline: now)
        store.setStatus(.received, for: r1)
        let r2 = store.addRebate(storeOrProduct: "B", amount: 30, purchaseDate: now, submissionDeadline: now)
        store.setStatus(.received, for: r2)
        store.addRebate(storeOrProduct: "C", amount: 100, purchaseDate: now, submissionDeadline: now) // not received

        XCTAssertEqual(store.totalReclaimedThisYear(referenceDate: now), 50, accuracy: 0.001)
    }

    func testTotalReclaimedExcludesDifferentYear() {
        let now = Date()
        let r1 = store.addRebate(storeOrProduct: "A", amount: 40, purchaseDate: now, submissionDeadline: now)
        store.setStatus(.received, for: r1)

        var futureComponents = Calendar.current.dateComponents([.year, .month, .day], from: now)
        futureComponents.year = (futureComponents.year ?? 2026) + 1
        let nextYear = Calendar.current.date(from: futureComponents)!

        XCTAssertEqual(store.totalReclaimedThisYear(referenceDate: nextYear), 0, accuracy: 0.001)
    }

    // MARK: - Total at risk

    func testTotalAtRiskOfExpiringSumsActiveRebatesWithinWindow() {
        let now = Date()
        let soonDeadline = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        let farDeadline = Calendar.current.date(byAdding: .day, value: 60, to: now)!

        store.addRebate(storeOrProduct: "Soon", amount: 20, purchaseDate: now, submissionDeadline: soonDeadline)
        store.addRebate(storeOrProduct: "Far", amount: 999, purchaseDate: now, submissionDeadline: farDeadline)

        let atRisk = store.totalAtRiskOfExpiring(withinDays: 14, referenceDate: now)
        XCTAssertEqual(atRisk, 20, accuracy: 0.001)
    }

    func testTotalAtRiskExcludesReceivedOrExpired() {
        let now = Date()
        let soonDeadline = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        let r = store.addRebate(storeOrProduct: "Soon", amount: 20, purchaseDate: now, submissionDeadline: soonDeadline)
        store.setStatus(.received, for: r)

        let atRisk = store.totalAtRiskOfExpiring(withinDays: 14, referenceDate: now)
        XCTAssertEqual(atRisk, 0, accuracy: 0.001)
    }
}
