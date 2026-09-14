import Foundation
import Security
import Testing
@testable import cmarks

/// 빌드된 앱의 서명에 든 엔타이틀먼트. Finder 따라가기(Apple Events)는 hardened runtime에서 이 엔타이틀먼트가 없으면 TCC가 프롬프트 없이 거부한다.
struct EntitlementTests {
    static func entitlements() throws -> [String: Any] {
        var code: SecCode?
        #expect(SecCodeCopySelf([], &code) == errSecSuccess)
        var staticCode: SecStaticCode?
        #expect(SecCodeCopyStaticCode(try #require(code), [], &staticCode) == errSecSuccess)
        var info: CFDictionary?
        #expect(SecCodeCopySigningInformation(try #require(staticCode), SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess)
        let dictionary = try #require(info as? [String: Any])
        return dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    }

    @Test func appMayAutomateOtherApps() throws {
        let entitlements = try Self.entitlements()
        #expect(entitlements["com.apple.security.automation.apple-events"] as? Bool == true, "\(entitlements)")
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == false)
    }
}
