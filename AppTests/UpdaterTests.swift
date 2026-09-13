import Foundation
import Testing
@testable import cmarks

/// Sparkle 설정과 appcast 피드의 형식. 실제 네트워크 검사는 하지 않는다(테스트 호스트에서는 업데이터를 켜지 않는다).
struct UpdaterTests {
    static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    @Test @MainActor func updaterStaysOffInTestHost() {
        let updater = UpdaterModel.shared
        #expect(updater.isAvailable == false)
        #expect(updater.canCheckForUpdates == false)
    }

    @Test func infoPlistDeclaresSparkleFeed() throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = try #require(info["SUFeedURL"] as? String)
        let url = try #require(URL(string: feed))
        #expect(url.scheme == "https")
        #expect(url.host == "raw.githubusercontent.com")
        #expect(url.path.hasSuffix("/appcast.xml"))
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        // 비어 있으면 release.sh가 appcast 생성을 거부한다. 값이 있으면 EdDSA 공개 키(32바이트 base64 = 44자)여야 한다.
        let key = info["SUPublicEDKey"] as? String ?? ""
        #expect(key.isEmpty || (key.count == 44 && Data(base64Encoded: key)?.count == 32), "SUPublicEDKey 형식: \(key)")
    }

    @Test func appcastIsWellFormedAndNewestFirst() throws {
        let doc = try XMLDocument(contentsOf: Self.repoRoot.appending(path: "appcast.xml"))
        let items = try doc.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
        var builds: [Int] = []
        for item in items {
            let enclosure = try #require(item.elements(forName: "enclosure").first)
            let url = enclosure.attribute(forName: "url")?.stringValue ?? ""
            #expect(url.hasPrefix("https://github.com/yuchanghyun/cmarks/releases/download/"), "enclosure url: \(url)")
            #expect(!(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue ?? "").isEmpty)
            #expect((Int(enclosure.attribute(forName: "length")?.stringValue ?? "") ?? 0) > 0)
            builds.append(try #require(Int(item.elements(forName: "sparkle:version").first?.stringValue ?? "")))
            #expect(item.elements(forName: "sparkle:minimumSystemVersion").first?.stringValue == "15.0")
            #expect(!(item.elements(forName: "description").first?.stringValue ?? "").isEmpty)
        }
        #expect(builds == builds.sorted(by: >))
    }
}
