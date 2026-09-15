import Foundation
import Observation

/// 앱 밖에서 들어온 "열기" 요청을 UI가 소비할 때까지 보관한다.
/// 파일 URL은 탭 열기, 폴더 URL은 워크스페이스 추가로 해석된다(Phase 1, Phase 4).
@MainActor
@Observable
final class OpenRequestQueue {
    static let shared = OpenRequestQueue()

    private(set) var pending: [URL] = []

    /// 실행이 끝난 뒤 설정된다. 이후의 요청은 UI(ContentView)를 기다리지 않고 바로 소비한다.
    /// 창을 모두 닫으면 ContentView가 사라져 큐를 비울 주체가 없어지므로(1.3.2에서 마지막 창을 닫은 뒤 Finder 열기가 무시됨)
    /// 실행 중에는 모델이 직접 소비해야 한다. 실행 시점의 요청은 첫 창이 뜨면 ContentView가 소비한다.
    var consumer: (() -> Void)?

    init() {}

    func enqueue(_ urls: [URL]) {
        pending.append(contentsOf: urls.compactMap(Self.fileURL(from:)))
        consumer?()
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
