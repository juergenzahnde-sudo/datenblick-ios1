import Foundation

/// Experimental adapter for the Telekom Pass website, not an official API contract.
/// Verified on 2026-10-17: https://pass.telekom.de/?lang=de_DE_TMDE documents
/// mobile-network/SMS authentication. The authenticated markup cannot be inspected
/// from this development environment. The observed class names come from the
/// author's published parser at:
/// https://www.reddit.com/r/Scriptable/comments/1wn9xwa/german_small_widget_for_telekom_mobile_data_usage/
/// Fixtures test our interpretation of that markup; they are not real account data.
/// Unknown layouts, units, and authentication pages must never overwrite the cache.
enum TelekomHTMLParser {
    static func decode(_ html: String, now: Date = Date()) throws -> UsageSnapshot {
        let document = Document(html)
        guard document.text.localizedCaseInsensitiveContains("Ihr Datenvolumen") else {
            throw ParseError.unsupportedPage
        }

        let remainingFields = document.elements(withClass: "remaining-volume-value")
        let totalFields = document.elements(withClass: "start-volume")
        guard remainingFields.count == 1, totalFields.count == 1 else {
            throw ParseError.unsupportedPage
        }

        let remaining = try document.volume(in: remainingFields[0])
        let total = try document.volume(in: totalFields[0])
        guard total.isFinite, total > 0, remaining.isFinite,
              remaining >= 0, remaining <= total else {
            throw ParseError.invalidVolume
        }

        return UsageSnapshot(
            usedBytes: total - remaining,
            totalBytes: total,
            cycleEnd: document.cycleEnd(relativeTo: now),
            fetchedAt: now,
            source: .telekom,
            isUnlimited: false,
            planName: "Telekom"
        )
    }

    enum ParseError: LocalizedError {
        case unsupportedPage
        case invalidVolume
        case missingUnit

        var errorDescription: String? {
            switch self {
            case .unsupportedPage:
                return "Die Telekom-Seite enthält keine eindeutig erkennbaren Verbrauchsdaten. Bitte Mobilfunkverbindung und Telekom-Anmeldung prüfen."
            case .invalidVolume:
                return "Die Verbrauchswerte der Telekom-Seite sind nicht eindeutig lesbar. Der letzte gültige Stand bleibt erhalten."
            case .missingUnit:
                return "Die Einheit des Datenvolumens ist auf der Telekom-Seite nicht eindeutig erkennbar. Der letzte gültige Stand bleibt erhalten."
            }
        }
    }

    private struct Element {
        let tag: String
        let classes: Set<String>
        let parent: Int?
        let contentStart: Int
        var contentEnd: Int?
    }

    /// A small, inert HTML reader restricted to text and semantic CSS classes.
    /// It never evaluates scripts or follows links. Class names must match whole
    /// tokens, and the relevant elements must have a matching closing tag.
    private struct Document {
        let source: NSString
        let elements: [Element]
        let text: String
        let isEnglish: Bool

        init(_ html: String) {
            let clean = html
                .replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
            source = clean as NSString
            text = Self.plainText(clean)
            isEnglish = clean.range(of: "<html\\b[^>]*\\blang\\s*=\\s*[\"']en(?:[-_][^\"']*)?[\"']", options: [.regularExpression, .caseInsensitive]) != nil

            let tokenPattern = "<\\s*(/?)\\s*([A-Za-z][A-Za-z0-9:-]*)\\b(?:\"[^\"]*\"|'[^']*'|[^'\">])*>"
            guard let tokenRegex = try? NSRegularExpression(pattern: tokenPattern) else {
                elements = []
                return
            }
            let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
            var parsed: [Element] = []
            var stack: [Int] = []
            for token in tokenRegex.matches(in: clean, range: NSRange(location: 0, length: source.length)) {
                let tag = source.substring(with: token.range(at: 2)).lowercased()
                let closing = token.range(at: 1).length > 0
                if closing {
                    if let stackPosition = stack.lastIndex(where: { parsed[$0].tag == tag }) {
                        let index = stack[stackPosition]
                        parsed[index].contentEnd = token.range.location
                        stack.removeSubrange(stackPosition...)
                    }
                } else {
                    let markup = source.substring(with: token.range)
                    let classes = Self.capture("(?:^|\\s)class\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", in: markup)
                    let index = parsed.count
                    parsed.append(Element(
                        tag: tag,
                        classes: Set((classes ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)),
                        parent: stack.last,
                        contentStart: NSMaxRange(token.range),
                        contentEnd: nil
                    ))
                    if !voidTags.contains(tag), !markup.hasSuffix("/>") {
                        stack.append(index)
                    }
                }
            }
            elements = parsed
        }

        func elements(withClass name: String) -> [Int] {
            elements.indices.filter { elements[$0].classes.contains(name) && elements[$0].contentEnd != nil }
        }

        func content(of index: Int) -> String? {
            let element = elements[index]
            guard let end = element.contentEnd, end >= element.contentStart else { return nil }
            return Self.plainText(source.substring(with: NSRange(location: element.contentStart, length: end - element.contentStart)))
        }

        func volume(in index: Int) throws -> Double {
            guard let field = content(of: index) else { throw ParseError.invalidVolume }
            if let value = try parseVolume(field) { return value }

            // New markup may put the unit in a neighbouring span. Only accept it
            // when the nearest compact enclosing element contains exactly this
            // number and its unit. Never infer GB from another field or a tariff.
            guard Self.capture("^\\s*([0-9][0-9.,\\s’']*)\\s*$", in: field) != nil else {
                throw ParseError.invalidVolume
            }
            var parent = elements[index].parent
            for _ in 0..<2 {
                guard let current = parent else { break }
                if let enclosing = content(of: current), enclosing.count <= 80,
                   let value = try parseVolume(enclosing) {
                    return value
                }
                parent = elements[current].parent
            }
            throw ParseError.missingUnit
        }

        func parseVolume(_ value: String) throws -> Double? {
            let expression = "^\\s*([0-9][0-9.,\\s’']*)\\s*(bytes?|[KMGT]?i?B)\\s*$"
            guard let regex = try? NSRegularExpression(pattern: expression, options: .caseInsensitive),
                  let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else {
                return nil
            }
            let input = value as NSString
            let number = input.substring(with: match.range(at: 1))
            let unit = input.substring(with: match.range(at: 2)).lowercased()
            guard let amount = localizedNumber(number), amount.isFinite, amount >= 0 else {
                throw ParseError.invalidVolume
            }
            let factors: [String: Double] = [
                "b": 1, "byte": 1, "bytes": 1,
                "kb": 1_000, "mb": 1_000_000, "gb": 1_000_000_000, "tb": 1_000_000_000_000,
                "kib": 1_024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776
            ]
            guard let factor = factors[unit], (amount * factor).isFinite else {
                throw ParseError.invalidVolume
            }
            return amount * factor
        }

        func localizedNumber(_ input: String) -> Double? {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.replacingOccurrences(of: "[\\s’']+", with: " ", options: .regularExpression)
            let decimal: Character = isEnglish ? "." : ","
            let grouping: Character = isEnglish ? "," : "."
            let parts = value.split(separator: decimal, omittingEmptySubsequences: false)
            guard parts.count <= 2, !parts[0].isEmpty else { return nil }
            if parts.count == 2 {
                guard !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            }
            // A thousands separator may be a locale separator, a nonbreaking
            // space, or an apostrophe. Validate grouping before removing it.
            let integer = parts[0].replacingOccurrences(of: " ", with: String(grouping))
            let groups = integer.split(separator: grouping, omittingEmptySubsequences: false)
            guard !groups.isEmpty, groups[0].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            if groups.count > 1 {
                guard (1...3).contains(groups[0].count),
                      groups.dropFirst().allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
            }
            let normalized = groups.joined() + (parts.count == 2 ? "." + String(parts[1]) : "")
            return Double(normalized)
        }

        func cycleEnd(relativeTo now: Date) -> Date? {
            let names = ["days", "hours", "mins", "secs"]
            var values: [Double] = []
            for name in names {
                let fields = elements(withClass: name)
                guard fields.count == 1, let field = content(of: fields[0]),
                      let digits = Self.capture("^\\s*([0-9]+)(?:\\s*(?:Tage?|days?|Std\\.?|Stunden?|hours?|Min\\.?|Minuten?|minutes?|Sek\\.?|Sekunden?|seconds?))?\\s*$", in: field),
                      let value = Double(digits), value.isFinite else { return nil }
                values.append(value)
            }
            guard values[0] <= 366, values[1] < 24, values[2] < 60, values[3] < 60 else { return nil }
            let seconds = values[0] * 86_400 + values[1] * 3_600 + values[2] * 60 + values[3]
            guard seconds > 0 else { return nil }
            return now.addingTimeInterval(seconds)
        }

        static func plainText(_ html: String) -> String {
            let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            var result = stripped
            let entities = ["&nbsp;": " ", "&thinsp;": " ", "&ensp;": " ", "&emsp;": " ", "&amp;": "&", "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">"]
            for (entity, replacement) in entities {
                result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
            }
            if let numeric = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
                for match in numeric.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length)).reversed() {
                    let encoded = (result as NSString).substring(with: match.range(at: 1))
                    let scalar = encoded.lowercased().hasPrefix("x") ? UInt32(encoded.dropFirst(), radix: 16) : UInt32(encoded)
                    if let scalar, let character = UnicodeScalar(scalar) {
                        result = (result as NSString).replacingCharacters(in: match.range, with: String(character))
                    }
                }
            }
            return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func capture(_ expression: String, in value: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: expression, options: .caseInsensitive),
                  let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else { return nil }
            for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                return (value as NSString).substring(with: match.range(at: index))
            }
            return nil
        }
    }
}
