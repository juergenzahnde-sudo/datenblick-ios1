import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum TelekomError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidVolume
    case network(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Die Telekom hat keine lesbaren Verbrauchsdaten geliefert."
        case .httpStatus(let code):
            return "Die Telekom-Abfrage ist momentan nicht verfügbar (HTTP \(code))."
        case .invalidVolume:
            return "Die Telekom-Antwort enthält keine gültigen Angaben zum Datenvolumen."
        case .network(let message):
            return "Die Verbindung zur Telekom ist fehlgeschlagen. \(message)"
        case .unavailable:
            return "Keine Telekom-Daten verfügbar. Versuche es im Telekom-Mobilfunknetz bei ausgeschaltetem WLAN und VPN. Der Datenpass-Zugang kann je nach Tarif nicht verfügbar sein."
        }
    }
}

struct TelekomClient {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    /// The Telekom data-pass interfaces are undocumented and may change.
    /// Both adapters must return actual valid values; failures never create demo data.
    func fetch() async throws -> UsageSnapshot {
        do {
            let json = try await request(path: "/api/service/generic/v1/status", accept: "application/json")
            return try Self.decode(json)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            do {
                let data = try await request(path: "/home", accept: "text/html")
                guard let html = String(data: data, encoding: .utf8) else {
                    throw TelekomError.invalidResponse
                }
                return try TelekomHTMLParser.decode(html)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if let networkError = error as? URLError {
                    throw TelekomError.network(networkError.localizedDescription)
                }
                throw TelekomError.unavailable
            }
        }
    }

    private func request(path: String, accept: String) async throws -> Data {
        guard let url = URL(string: "https://pass.telekom.de" + path) else {
            throw TelekomError.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TelekomError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            throw TelekomError.httpStatus(response.statusCode)
        }
        guard response.url?.scheme == "https", response.url?.host == "pass.telekom.de",
              data.count <= 2_000_000 else { throw TelekomError.invalidResponse }
        return data
    }

    /// Parse numbers or numeric strings without guessing units from human-readable labels.
    static func decode(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw TelekomError.invalidResponse }
        guard let root = object as? [String: Any] else { throw TelekomError.invalidResponse }
        let fields: [String: Any]
        if root["usedVolume"] == nil, let nested = root["data"] as? [String: Any] {
            fields = nested
        } else {
            fields = root
        }
        guard let used = number(fields["usedVolume"]), used.isFinite, used >= 0 else {
            throw TelekomError.invalidVolume
        }
        let unlimited = boolean(fields["isUnlimited"]) || boolean(fields["unlimited"])
            || (fields["passType"] as? String)?.lowercased() == "unlimited"
        let total = number(fields["initialVolume"])
        if let total, !total.isFinite || total < 0 { throw TelekomError.invalidVolume }
        guard unlimited || total != nil else { throw TelekomError.invalidVolume }

        var end = date(fields["cycleEnd"]) ?? date(fields["endDate"])
        if end == nil, let seconds = number(fields["remainingSeconds"]), seconds.isFinite, seconds >= 0,
           seconds <= 10 * 366 * 86_400 {
            end = now.addingTimeInterval(seconds)
        }
        let start = date(fields["cycleStart"]) ?? date(fields["startDate"])
        let planName = [fields["planName"], fields["passName"]]
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return UsageSnapshot(
            usedBytes: used,
            totalBytes: unlimited ? nil : total,
            cycleStart: start,
            cycleEnd: end,
            fetchedAt: now,
            source: .telekom,
            isUnlimited: unlimited,
            planName: planName.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() {
            return value.boolValue
        }
        return (value as? String)?.lowercased() == "true"
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = number(value), timestamp.isFinite, timestamp >= 0 {
            let seconds = timestamp > 100_000_000_000 ? timestamp / 1_000 : timestamp
            guard seconds <= 253_402_300_799 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
