import Foundation
import XCTest
@testable import DatenblickCore

final class AppGroupResolverTests: XCTestCase {
    private let configured = "group.de.datenblick.app"
    private let team = "A1B2C3D4E5"

    private func profile(groups: [String], teams: [String]? = ["A1B2C3D4E5"], cms: Bool = false) throws -> Data {
        var dictionary: [String: Any] = ["Entitlements": ["com.apple.security.application-groups": groups]]
        if let teams { dictionary["TeamIdentifier"] = teams }
        let xml = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        guard cms else { return xml }
        // Synthetic CMS-like envelope tests extraction, not signature verification.
        return Data([0x30, 0x82, 0xff, 0x00]) + xml + Data([0x00, 0xff])
    }

    func testMissingProfilePreservesConfiguredGroupForSimulator() {
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: nil), configured)
    }

    func testUnchangedProvisionedGroupUsesExactMatch() throws {
        let data = try profile(groups: ["group.unrelated", configured])
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data), configured)
    }

    func testAltStoreSuffixResolvesFromOwnCMSMetadata() throws {
        let mapped = configured + "." + team
        let data = try profile(groups: ["group.unrelated", mapped], cms: true)
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data), mapped)
    }

    func testInjectedAltStoreGroupsResolveWithoutProfile() {
        let mapped = configured + "." + team
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: nil,
                                               altAppGroups: ["group.unrelated", mapped]), mapped)
    }

    func testNoSubstringOrUnrelatedGroupFallback() throws {
        for group in ["group.unrelated", "group.prefix.de.datenblick.app." + team,
                      configured + "-copy." + team, configured + ".shared." + team,
                      configured + ".short", configured + ".a1b2c3d4e5"] {
            let data = try profile(groups: [group])
            XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data), configured)
        }
    }

    func testTeamIdentifierMustAgreeWithDecodedProfile() throws {
        let data = try profile(groups: [configured + ".Z9Y8X7W6V5"])
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data), configured)
    }

    func testMultipleMappedGroupsAreAmbiguousWithoutTeam() {
        let groups = [configured + "." + team, configured + ".Z9Y8X7W6V5"]
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: nil, altAppGroups: groups), configured)
    }

    func testProfileDisambiguatesMultipleTeamsAndTakesPrecedenceOverInjectedMetadata() throws {
        let mapped = configured + "." + team
        let data = try profile(groups: [mapped, configured + ".Z9Y8X7W6V5"])
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data,
                                               altAppGroups: [configured + ".Q1W2E3R4T5"]), mapped)
    }

    func testMalformedOrOversizedMetadataDoesNotSelectAnotherContainer() {
        for data in [Data(), Data("<plist><dict>broken</dict>".utf8), Data(repeating: 0xff, count: 2 * 1_024 * 1_024 + 1)] {
            XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data,
                                                   altAppGroups: ["group.unrelated"]), configured)
        }
    }

    func testMultipleEmbeddedPlistsAreRejected() throws {
        let first = try profile(groups: [configured + "." + team], cms: true)
        let second = try profile(groups: [configured + ".Z9Y8X7W6V5"], cms: true)
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: first + second), configured)
    }

    func testExactMatchWinsOverMappedVariant() throws {
        let data = try profile(groups: [configured, configured + "." + team])
        XCTAssertEqual(AppGroupResolver.resolve(configured: configured, profileData: data), configured)
    }
}
