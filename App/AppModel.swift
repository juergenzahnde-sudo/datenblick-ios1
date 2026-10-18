import Foundation
import Combine
import UserNotifications
import WidgetKit

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var settings: AppSettings
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var history: [UsageSnapshot]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var notice: String?

    private let store = SharedStore()
    private let client = TelekomClient()
    private let preferences = UserDefaults.standard
    private let setupKey = "Datenblick.hasCompletedSetup"
    private let warningKeyPrefix = "Datenblick.lastWarningCycle."
    private var lastAutomaticRefresh: Date?
    private var configurationGeneration = 0
    private var permissionGeneration = 0

    override init() {
        let initialStore = SharedStore()
        settings = initialStore.settings
        snapshot = initialStore.snapshot
        history = initialStore.history
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var sourceTitle: String {
        switch settings.mode {
        case .telekom: return "Telekom"
        case .manual: return "Manuell"
        case .demo: return "Demo"
        }
    }

    var selectedHistory: [UsageSnapshot] {
        history.filter { record in
            switch (settings.mode, record.source) {
            case (.telekom, .telekom), (.manual, .manual), (.demo, .demo): return true
            default: return false
            }
        }.sorted { $0.fetchedAt < $1.fetchedAt }
    }

    /// Foreground refreshes are intentionally throttled. iOS controls background/widget budgets.
    func refreshIfConfigured() async {
        reloadFromStore()
        guard preferences.bool(forKey: setupKey), case .telekom = settings.mode else { return }
        if let last = lastAutomaticRefresh, Date().timeIntervalSince(last) < 300 { return }
        lastAutomaticRefresh = Date()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        lastError = nil
        notice = nil
        switch settings.mode {
        case .demo:
            persist(.demo())
            notice = "Beispieldaten aktualisiert. Dies ist kein echter Telekom-Verbrauch."
        case .manual:
            notice = "Manuelle Werte aktualisierst du in den Einstellungen."
        case .telekom:
            let generation = configurationGeneration
            preferences.set(true, forKey: setupKey)
            isRefreshing = true
            defer { isRefreshing = false }
            do {
                let result = try await client.fetch()
                guard generation == configurationGeneration, settings.mode == .telekom else { return }
                persist(result)
                await checkWarning(for: result)
            } catch is CancellationError {
                // Keep the last successful reading if the task is cancelled.
            } catch {
                guard generation == configurationGeneration, settings.mode == .telekom else { return }
                lastError = error.localizedDescription
            }
        }
    }

    func useTelekom(planName: String) async {
        configurationGeneration += 1
        var updated = settings
        updated.mode = .telekom
        updated.planName = cleanedPlanName(planName)
        updateSettings(updated)
        reloadSelectedSource()
        await refresh()
    }

    func useDemo() {
        configurationGeneration += 1
        var updated = settings
        updated.mode = .demo
        updateSettings(updated)
        lastError = nil
        notice = "Demomodus: Alle angezeigten Werte sind Beispieldaten."
        persist(.demo())
    }

    func saveManual(planName: String, totalText: String, usedText: String, startDay: Int) async -> Bool {
        guard let total = Self.parseNumber(totalText), total >= 0.1, total <= 10_000 else {
            lastError = "Bitte gib ein Datenvolumen von 0,1 bis 10.000 GB ein."
            return false
        }
        guard let used = Self.parseNumber(usedText), used >= 0, used <= 10_000 else {
            lastError = "Bitte gib einen Verbrauch von 0 bis 10.000 GB ein."
            return false
        }
        configurationGeneration += 1
        let day = min(31, max(1, startDay))
        let dates = BillingCycle.dates(startDay: day, now: Date())
        var updated = settings
        updated.mode = .manual
        updated.monthlyLimitGB = total
        updated.cycleStartDay = day
        updated.planName = cleanedPlanName(planName)
        updateSettings(updated)
        let result = UsageSnapshot(
            usedBytes: used * 1_000_000_000,
            totalBytes: total * 1_000_000_000,
            cycleStart: dates.start,
            cycleEnd: dates.end,
            fetchedAt: Date(),
            source: .manual,
            isUnlimited: false,
            planName: updated.planName
        )
        lastError = nil
        notice = "Manuellen Verbrauch gespeichert. Eine automatische Verbrauchsmessung findet in diesem Modus nicht statt."
        persist(result)
        await checkWarning(for: result)
        return true
    }

    func setWarningThreshold(_ threshold: Int) {
        var updated = settings
        updated.warningThreshold = threshold
        updateSettings(updated)
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        permissionGeneration += 1
        let operation = permissionGeneration
        let generation = configurationGeneration
        guard enabled else {
            var updated = settings
            updated.notificationsEnabled = false
            updateSettings(updated)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["datenblick.usage-warning"])
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard operation == permissionGeneration, generation == configurationGeneration else { return }
            var updated = settings
            updated.notificationsEnabled = granted
            updateSettings(updated)
            if granted {
                notice = "Warnungen sind aktiv. Sie werden bei der nächsten erfolgreichen Aktualisierung in der geöffneten App geprüft."
            } else {
                notice = "Mitteilungen sind nicht erlaubt. Du kannst sie in den iOS-Einstellungen für Datenblick aktivieren."
            }
        } catch {
            guard operation == permissionGeneration, generation == configurationGeneration else { return }
            var updated = settings
            updated.notificationsEnabled = false
            updateSettings(updated)
            lastError = "Die Berechtigung für Mitteilungen konnte nicht abgefragt werden. Bitte versuche es erneut."
        }
    }

    func deleteLocalData() {
        configurationGeneration += 1
        permissionGeneration += 1
        store.clear()
        preferences.removeObject(forKey: setupKey)
        for source in ["telekom", "manual", "demo"] {
            preferences.removeObject(forKey: warningKeyPrefix + source)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["datenblick.usage-warning"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["datenblick.usage-warning"])
        settings = AppSettings()
        store.settings = settings
        snapshot = nil
        history = []
        lastError = nil
        notice = "Lokale Verbrauchsdaten und Einstellungen wurden gelöscht."
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateSettings(_ value: AppSettings) {
        settings = value
        store.settings = value
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reloadSelectedSource() {
        history = store.history
        snapshot = store.snapshot
    }

    private func reloadFromStore() {
        let storedSettings = store.settings
        if settings != storedSettings {
            configurationGeneration += 1
            settings = storedSettings
        }
        snapshot = store.snapshot
        // The extension only updates its latest cache. Opening the app records
        // that actual reading in the app-owned history, with timestamp deduplication.
        if let snapshot { store.save(snapshot) }
        history = store.history
    }

    private func persist(_ result: UsageSnapshot) {
        store.save(result)
        snapshot = store.snapshot
        history = store.history
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func cleanedPlanName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mein Telekom-Tarif" : String(trimmed.prefix(80))
    }

    private func checkWarning(for result: UsageSnapshot) async {
        let generation = configurationGeneration
        guard settings.notificationsEnabled, !result.isUnlimited,
              let total = result.totalBytes, total > 0,
              result.usedBytes / total * 100 >= Double(settings.warningThreshold) else { return }
        if case .demo = result.source { return }
        let auth = await UNUserNotificationCenter.current().notificationSettings()
        guard generation == configurationGeneration, settings.notificationsEnabled,
              settings.mode.source == result.source,
              result.usedBytes / total * 100 >= Double(settings.warningThreshold) else { return }
        guard auth.authorizationStatus == .authorized || auth.authorizationStatus == .provisional else { return }
        let cycle = warningCycle(for: result)
        let warningKey = warningKeyPrefix + result.source.rawValue
        guard preferences.string(forKey: warningKey) != cycle else { return }
        let content = UNMutableNotificationContent()
        content.title = "Dein Datenvolumen im Blick"
        content.body = "Mindestens \(settings.warningThreshold) % deines Datenvolumens sind verbraucht. Öffne Datenblick für den zuletzt gespeicherten Stand."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "datenblick.usage-warning", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            guard generation == configurationGeneration, settings.notificationsEnabled else {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["datenblick.usage-warning"])
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["datenblick.usage-warning"])
                return
            }
            preferences.set(cycle, forKey: warningKey)
        } catch {
            guard generation == configurationGeneration else { return }
            notice = "Der Verbrauch wurde gespeichert. Die Mitteilung konnte nicht zugestellt werden."
        }
    }

    private func warningCycle(for value: UsageSnapshot) -> String {
        let source: String
        switch value.source {
        case .telekom: source = "telekom"
        case .manual: source = "manual"
        case .demo: source = "demo"
        }
        if let start = value.cycleStart { return "\(source).\(Int(Calendar.current.startOfDay(for: start).timeIntervalSince1970))" }
        if let end = value.cycleEnd {
            // remainingSeconds-derived dates can differ by seconds near midnight.
            let stableDay = Calendar.current.startOfDay(for: end.addingTimeInterval(12 * 60 * 60))
            return "\(source).end.\(Int(stableDay.timeIntervalSince1970))"
        }
        let parts = Calendar.current.dateComponents([.year, .month], from: value.fetchedAt)
        return "\(source).\(parts.year ?? 0).\(parts.month ?? 0)"
    }

    static func parseNumber(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
