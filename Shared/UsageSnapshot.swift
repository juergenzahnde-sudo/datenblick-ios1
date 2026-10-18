import Foundation

enum UsageSource: String, Codable, Sendable {
    case telekom, manual, demo
}

enum DataMode: String, Codable, CaseIterable, Sendable {
    case telekom, manual, demo

    var source: UsageSource {
        switch self {
        case .telekom: return .telekom
        case .manual: return .manual
        case .demo: return .demo
        }
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    var usedBytes: Double
    var totalBytes: Double?
    var cycleStart: Date?
    var cycleEnd: Date?
    var fetchedAt: Date
    var source: UsageSource
    var isUnlimited: Bool
    var planName: String?

    init(
        usedBytes: Double,
        totalBytes: Double? = nil,
        cycleStart: Date? = nil,
        cycleEnd: Date? = nil,
        fetchedAt: Date = Date(),
        source: UsageSource,
        isUnlimited: Bool = false,
        planName: String? = nil
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.fetchedAt = fetchedAt
        self.source = source
        self.isUnlimited = isUnlimited
        self.planName = planName
    }

    /// Telecom quotas and manual input use decimal GB (1 GB = 1,000,000,000 bytes).
    var remainingBytes: Double? {
        guard !isUnlimited, let totalBytes, totalBytes.isFinite, totalBytes >= 0,
              usedBytes.isFinite else { return nil }
        return max(0, totalBytes - max(0, usedBytes))
    }

    var usedFraction: Double {
        guard !isUnlimited, let totalBytes, totalBytes.isFinite, totalBytes > 0,
              usedBytes.isFinite else { return 0 }
        return min(1, max(0, usedBytes / totalBytes))
    }

    var daysRemaining: Int? { daysRemaining(asOf: Date()) }

    func daysRemaining(asOf date: Date) -> Int? {
        guard let cycleEnd else { return nil }
        return max(0, Int(ceil(cycleEnd.timeIntervalSince(date) / 86_400)))
    }

    /// Widgets retain the last successful reading, but must label old readings clearly.
    var isStale: Bool { isStale(asOf: Date()) }

    func isStale(asOf date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > 2 * 60 * 60
    }

    static func demo(now: Date = Date()) -> UsageSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let end = calendar.date(byAdding: .month, value: 1, to: start)
        return UsageSnapshot(
            usedBytes: 12.4 * 1_000_000_000,
            totalBytes: 40 * 1_000_000_000,
            cycleStart: start,
            cycleEnd: end,
            fetchedAt: now,
            source: .demo,
            planName: "MagentaMobil · Demo"
        )
    }
}
