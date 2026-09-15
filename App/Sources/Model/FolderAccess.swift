import AppKit
import Foundation
import OSLog

/// 샌드박스 빌드(App Store 판)에서 사용자가 고른 폴더의 접근 권한을 보안 범위 북마크로 저장하고 재실행 뒤 되살린다.
/// 비샌드박스 빌드(GitHub 판)에서는 북마크를 만들지 않고(nil) 접근도 시작하지 않는다. 두 빌드가 같은 코드를 탄다(APPSTORE.md §2).
@MainActor
final class FolderAccess {
    /// 컨테이너 안에서 실행 중인가.
    nonisolated static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    private var started: Set<String> = []
    private let logger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "access")

    /// 지금 접근할 수 있는 폴더(열기 패널·드롭으로 넘어온 것)의 북마크. 만들 수 없으면(권한 없음·비샌드박스) nil.
    func makeBookmark(for url: URL) -> Data? {
        guard Self.isSandboxed else { return nil }
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            logger.notice("bookmark failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 북마크를 풀어 접근을 시작한다. 폴더가 옮겨졌으면 새 URL이 오고, 북마크가 낡았으면 새 북마크도 돌려준다. 풀지 못하면 nil.
    func restore(_ data: Data) -> (url: URL, refreshedBookmark: Data?)? {
        guard Self.isSandboxed else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            logger.notice("bookmark could not be resolved")
            return nil
        }
        start(url)
        return (url, stale ? makeBookmark(for: url) : nil)
    }

    /// 접근 시작. 앱이 살아 있는 동안(워크스페이스를 닫기 전까지) 유지한다.
    func start(_ url: URL) {
        guard Self.isSandboxed else { return }
        let key = url.standardizedFileURL.path(percentEncoded: false)
        guard !started.contains(key) else { return }
        if url.startAccessingSecurityScopedResource() { started.insert(key) }
    }

    func stop(_ url: URL) {
        let key = url.standardizedFileURL.path(percentEncoded: false)
        guard started.remove(key) != nil else { return }
        url.stopAccessingSecurityScopedResource()
    }

    /// 폴더 목록을 읽을 수 있는가(샌드박스가 아니면 권한 문제는 없다).
    nonisolated static func canList(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) != nil
    }
}
