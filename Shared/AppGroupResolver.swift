import Foundation

/// Resolves this app's own shared container after personal sideload signing.
/// AltStore Classic appends `.<team identifier>` to each original group, then
/// writes the provisioned groups into `ALTAppGroups` in both app and extension.
/// Primary implementation evidence, inspected 2026-10-17:
/// https://github.com/altstoreio/AltStore/blob/classic/AltStore/Operations/FetchProvisioningProfilesOperation.swift
/// https://github.com/altstoreio/AltStore/blob/classic/AltStore/Operations/ResignAppOperation.swift
/// https://github.com/altstoreio/AltStore/blob/classic/Shared/Extensions/Bundle+AltStore.swift
///
/// This reads metadata from our own bundle; it does not verify a CMS signature
/// or confer entitlements. iOS enforces the actual signed container permission.
/// Unknown signers/layouts fall back to the configured group rather than choosing
/// an unrelated provisioned group. No Apple account or profile leaves the device.
enum AppGroupResolver {
    private static let maximumProfileBytes = 2 * 1_024 * 1_024
    private static let entitlementKey = "com.apple.security.application-groups"

    static func resolve(bundle: Bundle = .main, configured: String) -> String {
        let profileURL = bundle.bundleURL.appendingPathComponent("embedded.mobileprovision")
        let profileData = readBoundedFile(profileURL)
        let injectedGroups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return resolve(configured: configured, profileData: profileData, altAppGroups: injectedGroups)
    }

    /// A pure entry point for fixtures and hosts that already loaded their own
    /// provisioning metadata. A missing profile is normal in the iOS simulator.
    static func resolve(configured: String, profileData: Data?, altAppGroups: [String] = []) -> String {
        guard isGroupIdentifier(configured) else { return configured }

        if let profileData, let profile = provisioningDictionary(profileData),
           let entitlements = profile["Entitlements"] as? [String: Any],
           let groups = entitlements[entitlementKey] as? [String] {
            let teams = (profile["TeamIdentifier"] as? [String] ?? []).filter(isTeamIdentifier)
            // A decoded provisioning profile takes precedence over optional
            // Info.plist metadata written by the sideloading application.
            return matchingGroup(configured: configured, groups: groups, teams: teams) ?? configured
        }

        // AltStore's own published runtime uses this Info.plist metadata. Limit
        // matches to the exact original group or its documented one-team suffix.
        return matchingGroup(configured: configured, groups: altAppGroups, teams: []) ?? configured
    }

    private static func matchingGroup(configured: String, groups: [String], teams: [String]) -> String? {
        guard groups.count <= 64 else { return nil }
        let validGroups = Set(groups.filter(isGroupIdentifier))
        if validGroups.contains(configured) { return configured }

        let prefix = configured + "."
        let candidates = validGroups.filter { group in
            guard group.hasPrefix(prefix) else { return false }
            let suffix = String(group.dropFirst(prefix.count))
            guard isTeamIdentifier(suffix) else { return false }
            return teams.isEmpty || teams.contains(suffix)
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func isTeamIdentifier(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy { byte in
            (byte >= 65 && byte <= 90) || (byte >= 48 && byte <= 57)
        }
    }

    private static func isGroupIdentifier(_ value: String) -> Bool {
        guard value.utf8.count <= 256, value.hasPrefix("group.") else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { byte in
                (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
                    || (byte >= 48 && byte <= 57) || byte == 45
            }
        }
    }

    private static func provisioningDictionary(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty, data.count <= maximumProfileBytes else { return nil }

        // Raw plists make deterministic fixtures possible and cover signers that
        // expose already-decoded metadata. Device profiles are normally CMS data.
        if let dictionary = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dictionary
        }

        // Apple embeds an XML plist inside the CMS envelope. Extract only that
        // bounded byte range; arbitrary binary bytes need not be valid UTF-8.
        let opening = Data("<plist".utf8)
        let closing = Data("</plist>".utf8)
        guard let start = data.range(of: opening),
              let end = data.range(of: closing, in: start.lowerBound..<data.endIndex) else { return nil }
        let afterOpening = start.upperBound..<data.endIndex
        guard data.range(of: opening, in: afterOpening) == nil else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)) as? [String: Any]
    }

    private static func readBoundedFile(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumProfileBytes + 1),
              data.count <= maximumProfileBytes else { return nil }
        return data
    }
}
