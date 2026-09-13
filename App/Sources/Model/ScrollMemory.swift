import Foundation

/// 파일별 마지막 스크롤 위치. 탭을 닫았다가 다시 열거나 앱을 다시 켜도 읽던 자리로 돌아간다. 최근 300개만 남긴다.
@MainActor
final class ScrollMemory {
    private let defaults: UserDefaults
    private let key = "scrollMemory"
    private let limit: Int
    /// 오래된 것부터. 값은 [경로, y].
    private var entries: [(path: String, y: Double)] = []
    private var saveTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, limit: Int = 300) {
        self.defaults = defaults
        self.limit = limit
        for item in defaults.array(forKey: key) as? [[Any]] ?? [] {
            if item.count == 2, let path = item[0] as? String, let y = item[1] as? Double { entries.append((path, y)) }
        }
    }

    func position(for url: URL) -> Double? {
        let path = url.standardizedFileURL.path
        return entries.last { $0.path == path }?.y
    }

    func remember(_ y: Double, for url: URL) {
        let path = url.standardizedFileURL.path
        entries.removeAll { $0.path == path }
        if y >= 1 { entries.append((path, y)) }
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        scheduleSave()
    }

    func forget(_ url: URL) {
        remember(0, for: url)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        defaults.set(entries.map { [$0.path, $0.y] as [Any] }, forKey: key)
    }
}
