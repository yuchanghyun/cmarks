import AppKit
import Foundation
import LayoutKit
import MarkdownCore
import Testing
import WebKit
@testable import cmarks

/// 실제 WKWebView와 렌더 파이프라인을 테스트 호스트 안에서 구동한다. 화면에 붙지 않아도 로드·JS·브릿지는 동작한다.
@MainActor
@Suite(.serialized)
struct ViewerIntegrationTests {
    @Test func rendersDocumentAndReportsReady() async throws {
        let dir = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: dir) }
        let viewer = PaneViewer(paneID: PaneID(), documents: DocumentService())
        viewer.open(DocumentRef(url: dir.appending(path: "kitchen-sink.md")))

        #expect(await waitUntil { viewer.isPageReady })
        #expect(viewer.stats?.jsReadyMS != nil)
        #expect(viewer.outline.contains { $0.id == "헤딩-1" }) // 중복 헤딩 슬러그
        let alerts = try await viewer.evaluate("document.querySelectorAll('.markdown-alert').length") as? Int
        #expect(alerts == 5)
        let tasks = try await viewer.evaluate("document.querySelectorAll('li.task-list-item input.task-list-item-checkbox').length") as? Int
        #expect(tasks == 3)
    }

    /// R-1: 새 검색이 이전 하이라이트를 지운다.
    @Test func findHighlightsAreReplacedBetweenSearches() async throws {
        let dir = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: dir) }
        let viewer = PaneViewer(paneID: PaneID(), documents: DocumentService())
        viewer.open(DocumentRef(url: dir.appending(path: "kitchen-sink.md")))
        #expect(await waitUntil { viewer.isPageReady })

        viewer.showFindBar()
        viewer.findQuery = "헤딩"
        await viewer.performFind()
        let first = viewer.findCount
        #expect(first > 1)
        let registered = try await viewer.evaluate("CSS.highlights.get('cmarks-find').size") as? Int
        #expect(registered == first)

        viewer.findQuery = "Mermaid"
        await viewer.performFind()
        let second = viewer.findCount
        #expect(second >= 1 && second != first)
        let afterSecond = try await viewer.evaluate("CSS.highlights.get('cmarks-find').size") as? Int
        #expect(afterSecond == second)
        let current = try await viewer.evaluate("CSS.highlights.get('cmarks-find-current').size") as? Int
        #expect(current == 1)

        viewer.hideFindBar()
        #expect(await waitUntil { viewer.findCount == 0 })
        let cleared = try await viewer.evaluate("CSS.highlights.get('cmarks-find').size") as? Int
        #expect(cleared == 0)
    }

    /// R-7·R-25: 마크다운 링크는 일반 클릭·⌘클릭·⌥클릭 모두 앱 안에서 처리된다.
    @Test func linkClicksWithModifiersStayInApp() async throws {
        let dir = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: dir) }
        let viewer = PaneViewer(paneID: PaneID(), documents: DocumentService())
        let capture = NavigationCapture()
        viewer.onNavigate = { ref, intent in capture.requests.append((ref, intent)) }
        let file = dir.appending(path: "links.md")
        try "# 링크\n\n[하위 문서](sub/linked.md)\n\n[둘째 절](sub/linked.md#둘째-절)\n".write(to: file, atomically: true, encoding: .utf8)
        viewer.open(DocumentRef(url: file))
        #expect(await waitUntil { viewer.isPageReady })

        let selector = "a[href=\"sub/linked.md\"]"
        _ = try await viewer.evaluate("(document.querySelector('\(selector)').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, metaKey: true })), true)")
        #expect(await waitUntil { capture.requests.count == 1 })
        #expect(capture.requests.last?.1 == .newTab)
        #expect(capture.requests.last?.0.url.lastPathComponent == "linked.md")

        _ = try await viewer.evaluate("(document.querySelector('\(selector)').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, altKey: true })), true)")
        #expect(await waitUntil { capture.requests.count == 2 })
        #expect(capture.requests.last?.1 == .newSplit(.right))

        _ = try await viewer.evaluate("(document.querySelector('\(selector)').click(), true)")
        #expect(await waitUntil { capture.requests.count == 3 })
        #expect(capture.requests.last?.1 == .sameTab)
        // 앵커가 있는 링크는 fragment도 전달된다
        // cmark는 앵커의 한글을 퍼센트 인코딩한다. 앱은 디코딩된 fragment를 넘겨야 한다.
        _ = try await viewer.evaluate("(document.querySelector('a[href^=\"sub/linked.md#\"]').click(), true)")
        #expect(await waitUntil { capture.requests.count == 4 })
        #expect(capture.requests.last?.0.fragment == "둘째-절")
        // 페이지는 그대로 남아 있다(이동은 취소되고 모델이 처리)
        #expect(viewer.currentURL?.lastPathComponent == "links.md")
    }

    /// R-23: 5MB 넘는 문서는 앞부분만 보이고 "전체 표시"로 전부 볼 수 있다.
    @Test func hugeDocumentIsTruncatedUntilFullLoad() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cmarks-huge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "huge.md")
        let body = try String(contentsOf: repositoryFixtures.appending(path: "kitchen-sink.md"), encoding: .utf8)
        try String(repeating: body, count: 1300).write(to: file, atomically: true, encoding: .utf8) // ≈7MB

        let documents = DocumentService()
        let viewer = PaneViewer(paneID: PaneID(), documents: documents)
        viewer.open(DocumentRef(url: file))
        #expect(await waitUntil(timeout: .seconds(30)) { viewer.isPageReady })
        #expect(documents.rendered[file.path]?.isTruncated == true)
        #expect(documents.rendered[file.path]?.isLarge == true)
        let hasButton = try await viewer.evaluate("document.getElementById('cmarks-load-full') !== null") as? Bool
        #expect(hasButton == true)
        let largeClass = try await viewer.evaluate("document.getElementById('doc').classList.contains('cmarks-large')") as? Bool
        #expect(largeClass == true)
        let highlighted = try await viewer.evaluate("document.querySelectorAll('code.hljs').length") as? Int
        #expect(highlighted == 0)

        _ = try await viewer.evaluate("(document.getElementById('cmarks-load-full').click(), true)")
        #expect(await waitUntil(timeout: .seconds(60)) { documents.rendered[file.path]?.isTruncated == false })
        #expect(await waitUntil(timeout: .seconds(60)) { viewer.isPageReady })
        let stillButton = try await viewer.evaluate("document.getElementById('cmarks-load-full') !== null") as? Bool
        #expect(stillButton == false)
    }

    /// R-11: 본문 폭은 다시 렌더 없이 바로 바뀐다.
    @Test func applyConfigChangesContentWidthImmediately() async throws {
        let dir = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: dir) }
        let viewer = PaneViewer(paneID: PaneID(), documents: DocumentService())
        viewer.open(DocumentRef(url: dir.appending(path: "한글 문서.md")))
        #expect(await waitUntil { viewer.isPageReady })
        let before = try await viewer.evaluate("getComputedStyle(document.getElementById('doc')).maxWidth") as? String
        #expect(before == "980px")
        viewer.applyConfig(["contentMaxWidth": NSNull()])
        #expect(await waitUntilAsync { (try? await viewer.evaluate("getComputedStyle(document.getElementById('doc')).maxWidth")) as? String == "none" })
        viewer.applyConfig(["contentMaxWidth": 700])
        #expect(await waitUntilAsync { (try? await viewer.evaluate("getComputedStyle(document.getElementById('doc')).maxWidth")) as? String == "700px" })
    }

    /// Phase 2 회귀: 파일이 바뀌면 바뀐 블록만 제자리에서 갱신된다.
    @Test func liveReloadMorphsChangedContent() async throws {
        let dir = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "live.md")
        try "# 제목\n\n첫 문단.\n\n## 둘째\n\n둘째 문단.\n".write(to: file, atomically: true, encoding: .utf8)
        let viewer = PaneViewer(paneID: PaneID(), documents: DocumentService())
        viewer.open(DocumentRef(url: file))
        #expect(await waitUntil { viewer.isPageReady })
        // 표식을 남겨 morph가 DOM을 통째로 갈아 끼우지 않았음을 확인한다
        _ = try await viewer.evaluate("(document.getElementById('제목').dataset.marker = 'kept', true)")

        try await Task.sleep(for: .milliseconds(300))
        try "# 제목\n\n첫 문단.\n\n## 둘째\n\n바뀐 문단.\n\n## 새 절\n\n추가.\n".write(to: file, atomically: false, encoding: .utf8)
        #expect(await waitUntil { viewer.stats?.changedBlocks != nil })
        let text = try await viewer.evaluate("document.getElementById('둘째').nextElementSibling.textContent") as? String
        #expect(text == "바뀐 문단.")
        let newSection = try await viewer.evaluate("document.getElementById('새-절') !== null") as? Bool
        #expect(newSection == true)
        let marker = try await viewer.evaluate("document.getElementById('제목').dataset.marker") as? String
        #expect(marker == "kept")
        #expect(viewer.outline.map(\.id) == ["제목", "둘째", "새-절"])
    }
}
