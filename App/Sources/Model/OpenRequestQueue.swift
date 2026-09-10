import Foundation
import Observation

/// 앱 밖에서 들어온 "열기" 요청을 UI가 소비할 때까지 보관한다.
/// 파일 URL은 탭 열기, 폴더 URL은 워크스페이스 추가로 해석된다(Phase 1, Phase 4).
@MainActor
@Observable
final class OpenRequestQueue {
    static let shared = OpenRequestQueue()

    private(set) var pending: [URL] = []

    init() {}

    func enqueue(_ urls: [URL]) {
        pending.append(contentsOf: urls.compactMap(Self.fileURL(from:)))
    }

    func drain() -> [URL] {
        defer { pending.removeAll() }
        return pending
    }

    /// file:// 은 그대로, `cmarks://open?path=…` 딥링크는 파일 URL로 바꾼다. 그 외는 버린다.
    static func fileURL(from url: URL) -> URL? {
        if url.isFileURL { return url }
        guard url.scheme?.lowercased() == "cmarks",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let path = items.first(where: { $0.name == "path" })?.value,
              !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
