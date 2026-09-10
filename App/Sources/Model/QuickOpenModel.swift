import FileKit
import Foundation

/// 빠른 열기(⌘P) 상태. 워크스페이스의 마크다운 파일을 색인하고 fuzzy로 고른다.
@MainActor
@Observable
final class QuickOpenModel {
    struct Result: Identifiable, Equatable {
        let url: URL
        let relativePath: String
        let score: Int
        var id: URL { url }
    }

    private struct Entry: Sendable {
        let url: URL
        let relativePath: String
        let fileNameStart: Int
    }

    var isPresented = false
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [Result] = []
    var selectedIndex = 0
    private(set) var isIndexing = false
    var filter = FileFilter.default
    /// 최근 연 파일. 앞이 최신. 점수 가산과 빈 질문의 기본 목록에 쓴다.
    var recents: [URL] = []

    private var entries: [Entry] = []
    private var indexedRoot: URL?
    private var indexStale = true
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    var selected: Result? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func present(root: URL?) {
        isPresented = true
        query = ""
        selectedIndex = 0
        if root?.standardizedFileURL != indexedRoot {
            indexedRoot = root?.standardizedFileURL
            indexStale = true
        }
        if indexStale { reindex() } else { search() }
    }

    func dismiss() {
        isPresented = false
        indexTask?.cancel()
        searchTask?.cancel()
    }

    /// 파일 트리가 바뀌었을 때. 다음 표시 때 다시 색인한다(열려 있으면 바로).
    func invalidateIndex() {
        indexStale = true
        if isPresented { reindex() }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    private func reindex() {
        indexTask?.cancel()
        guard let root = indexedRoot else {
            entries = []
            indexStale = false
            search()
            return
        }
        isIndexing = true
        let filter = self.filter
        indexTask = Task.detached(priority: .userInitiated) { [weak self] in
            let files = FileIndexer.markdownFiles(under: root, filter: filter)
            let rootPath = FileTreeModel.realPath(root.path(percentEncoded: false)) + "/"
            let entries = files.map { url -> Entry in
                let real = FileTreeModel.realPath(url.path(percentEncoded: false))
                let relative = real.hasPrefix(rootPath) ? String(real.dropFirst(rootPath.count)) : url.lastPathComponent
                let start = relative.lastIndex(of: "/").map { relative.distance(from: relative.startIndex, to: $0) + 1 } ?? 0
                return Entry(url: url, relativePath: relative, fileNameStart: start)
            }
            guard !Task.isCancelled else { return }
            await self?.applyIndex(entries)
        }
    }

    private func applyIndex(_ entries: [Entry]) {
        self.entries = entries
        isIndexing = false
        indexStale = false
        search()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.search()
        }
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let known = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0.relativePath) })
            results = recents.prefix(12).map { url in
                Result(url: url, relativePath: known[url] ?? url.path(percentEncoded: false).abbreviatingWithTilde, score: 0)
            }
            selectedIndex = 0
            return
        }
        let recentSet = Set(recents.prefix(50))
        var scored: [Result] = []
        scored.reserveCapacity(64)
        for entry in entries {
            guard let match = FuzzyMatcher.match(trimmed, in: entry.relativePath, fileNameStart: entry.fileNameStart) else { continue }
            let bonus = recentSet.contains(entry.url) ? 25 : 0
            scored.append(Result(url: entry.url, relativePath: entry.relativePath, score: match.score + bonus))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.relativePath.count < $1.relativePath.count }
        results = Array(scored.prefix(12))
        selectedIndex = 0
    }
}

extension String {
    var abbreviatingWithTilde: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
