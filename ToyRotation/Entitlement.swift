import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen = Date()
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var purchasedPro = false

    var trialStart: Date {
        let firstPaidOpen = proStartedAt ?? firstOpen
        return min(firstPaidOpen, trialClaimedAt ?? firstPaidOpen)
    }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || (now >= trialStart && now < trialEnd)
    }

    func trialDaysLeft(at now: Date) -> Int {
        max(0, Int(ceil(trialEnd.timeIntervalSince(now) / 86_400)))
    }
}
