import Foundation

/// App Group persistence shared by the iOS app and WidgetKit extension.
/// Each source has its own snapshot and history: switching modes never promotes
/// demo or manually entered readings to a live Telekom reading.
final class SharedStore {
    static let defaultAppGroup = "group.de.datenblick.app"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let prefix = "datenblick.v1."

    convenience init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        let group = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalGroup = group.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultAppGroup
        let suiteName = AppGroupResolver.resolve(configured: originalGroup)
        self.init(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    /// Dependency injection keeps tests isolated from the user's App Group.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var settings: AppSettings {
        get { read(AppSettings.self, key: prefix + "settings")?.normalized ?? AppSettings() }
        set { write(newValue.normalized, key: prefix + "settings") }
    }

    /// Clearing the data invalidates requests already running in the widget.
    var generation: String { defaults.string(forKey: prefix + "generation") ?? "initial" }

    var snapshot: UsageSnapshot? {
        get {
            let expected = settings.mode.source
            guard let value = read(UsageSnapshot.self, key: snapshotKey(expected)),
                  value.source == expected else { return nil }
            return value
        }
        set {
            if let newValue {
                save(newValue)
            } else {
                defaults.removeObject(forKey: snapshotKey(settings.mode.source))
            }
        }
    }

    /// Oldest first, with a maximum of 90 successful readings per source.
    var history: [UsageSnapshot] { history(for: settings.mode.source) }

    /// Widgets update only the latest cache (`recordHistory: false`); the app is
    /// the sole history writer. UserDefaults does not provide cross-process
    /// transactions, so the age check prevents sequential regressions, not every
    /// possible simultaneous read/write race between app and extension.
    func save(_ snapshot: UsageSnapshot, recordHistory: Bool = true) {
        guard snapshot.usedBytes.isFinite, snapshot.usedBytes >= 0,
              snapshot.totalBytes.map({ $0.isFinite && $0 >= 0 }) ?? true else { return }
        if let current = read(UsageSnapshot.self, key: snapshotKey(snapshot.source)),
           current.fetchedAt > snapshot.fetchedAt {
            return
        }
        write(snapshot, key: snapshotKey(snapshot.source))
        guard recordHistory else { return }
        var readings = history(for: snapshot.source)
        readings.removeAll { $0.fetchedAt == snapshot.fetchedAt }
        readings.append(snapshot)
        readings.sort { $0.fetchedAt < $1.fetchedAt }
        write(Array(readings.suffix(90)), key: historyKey(snapshot.source))
    }

    /// Clear local settings and every source's readings, without touching other apps.
    func clear() {
        defaults.set(UUID().uuidString, forKey: prefix + "generation")
        defaults.removeObject(forKey: prefix + "settings")
        for source in [UsageSource.telekom, .manual, .demo] {
            defaults.removeObject(forKey: snapshotKey(source))
            defaults.removeObject(forKey: historyKey(source))
        }
    }

    private func snapshotKey(_ source: UsageSource) -> String { prefix + "snapshot." + source.rawValue }
    private func historyKey(_ source: UsageSource) -> String { prefix + "history." + source.rawValue }

    private func history(for source: UsageSource) -> [UsageSnapshot] {
        let readings = read([UsageSnapshot].self, key: historyKey(source)) ?? []
        return readings.filter { $0.source == source }
    }

    private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
