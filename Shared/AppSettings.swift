import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var mode: DataMode
    var monthlyLimitGB: Double
    var cycleStartDay: Int
    var warningThreshold: Int
    var notificationsEnabled: Bool
    var planName: String

    init(
        mode: DataMode = .telekom,
        monthlyLimitGB: Double = 40,
        cycleStartDay: Int = 1,
        warningThreshold: Int = 80,
        notificationsEnabled: Bool = false,
        planName: String = "Mein Telekom-Tarif"
    ) {
        self.mode = mode
        self.monthlyLimitGB = monthlyLimitGB
        self.cycleStartDay = cycleStartDay
        self.warningThreshold = warningThreshold
        self.notificationsEnabled = notificationsEnabled
        self.planName = planName
    }

    var normalized: AppSettings {
        var value = self
        value.monthlyLimitGB = monthlyLimitGB.isFinite ? min(10_000, max(0.1, monthlyLimitGB)) : 40
        value.cycleStartDay = min(31, max(1, cycleStartDay))
        value.warningThreshold = min(100, max(1, warningThreshold))
        let trimmedName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.planName = trimmedName.isEmpty ? "Mein Telekom-Tarif" : String(trimmedName.prefix(80))
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case mode, monthlyLimitGB, cycleStartDay, warningThreshold, notificationsEnabled, planName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(DataMode.self, forKey: .mode) ?? .telekom
        monthlyLimitGB = try container.decodeIfPresent(Double.self, forKey: .monthlyLimitGB) ?? 40
        cycleStartDay = try container.decodeIfPresent(Int.self, forKey: .cycleStartDay) ?? 1
        warningThreshold = try container.decodeIfPresent(Int.self, forKey: .warningThreshold) ?? 80
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        planName = try container.decodeIfPresent(String.self, forKey: .planName) ?? "Mein Telekom-Tarif"
        self = normalized
    }
}
