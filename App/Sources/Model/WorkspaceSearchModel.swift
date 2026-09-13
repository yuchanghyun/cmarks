import FileKit
import Foundation

/// 워크스페이스 전체 텍스트 찾기(⌘⇧F). 마크다운 파일을 줄 단위로 훑어 대소문자 무시 부분 일치를 모은다.
@MainActor
@Observable
final class WorkspaceSearchModel {
    nonisolated struct Hit: Identifiable, Equatable, Sendable {
        let url: URL
        let relativePath: String
        /// 1부터 시작하는 줄 번호
        let line: Int
        /// 앞뒤를 잘라낸 줄 텍스트
        let snippet: String
        /// snippet 안에서 일치하는 구간
        let matchRange: Range<String.Index>
        /// 파일 안에서 몇 번째 일치인지(0부터). 찾기 바의 현재 위치를 맞추는 데 쓴다.
        let matchIndex: Int
        var id: String { "\(url.path)#\(line)#\(matchIndex)" }
    }

    nonisolated struct Summary: Equatable, Sendable {
        var hits: Int
        var files: Int
        var truncated: Bool
    }

    nonisolated static let minimumQueryLength = 2
    nonisolated static let maxHits = 300
    nonisolated static let maxHitsPerFile = 30
    nonisolated static let maxFileBytes = 4 << 20

    var isPresented = false
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [Hit] = []
    private(set) var summary = Summary(hits: 0, files: 0, truncated: false)
    private(set) var isSearching = false
    var selectedIndex = 0
    var filter = FileFilter.default
    private var root: URL?
    private var task: Task<Void, Never>?

    var selected: Hit? { results.indices.contains(selectedIndex) ? results[selectedIndex] : nil }

    func present(root: URL?) {
        self.root = root?.standardizedFileURL
        isPresented = true
        selectedIndex = 0
        if !query.isEmpty { scheduleSearch() }
    }

    func dismiss() {
        isPresented = false
        task?.cancel()
        isSearching = false
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    private func scheduleSearch() {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let root, trimmed.count >= Self.minimumQueryLength else {
            results = []
            summary = Summary(hits: 0, files: 0, truncated: false)
            isSearching = false
            return
        }
        isSearching = true
        let filter = self.filter
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let (hits, summary) = await Task.detached(priority: .userInitiated) {
                Self.scan(root: root, filter: filter, query: trimmed)
            }.value
            guard !Task.isCancelled else { return }
            self?.apply(hits, summary)
        }
    }

    private func apply(_ hits: [Hit], _ summary: Summary) {
        results = hits
        self.summary = summary
        selectedIndex = 0
        isSearching = false
    }

    /// 파일들을 훑는다. 검사 가능한 순수 함수: 파일 순서는 경로 순, 파일 안에서는 줄 순.
    nonisolated static func scan(root: URL, filter: FileFilter, query: String) -> ([Hit], Summary) {
        let needle = query.lowercased()
        let files = FileIndexer.markdownFiles(under: root, filter: filter).sorted { $0.path < $1.path }
        let rootPath = FileTreeModel.realPath(root.path(percentEncoded: false)) + "/"
        var hits: [Hit] = []
        var fileCount = 0
        var truncated = false
        for url in files {
            if Task.isCancelled { break }
            if hits.count >= maxHits { truncated = true; break }
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxFileBytes,
                  let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { continue }
            let real = FileTreeModel.realPath(url.path(percentEncoded: false))
            let relative = real.hasPrefix(rootPath) ? String(real.dropFirst(rootPath.count)) : url.lastPathComponent
            var fileHits = 0
            var matchIndex = 0
            var lineNumber = 0
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lineNumber += 1
                let lower = line.lowercased()
                guard lower.contains(needle) else { continue }
                var searchStart = lower.startIndex
                while let range = lower.range(of: needle, range: searchStart..<lower.endIndex) {
                    if fileHits < maxHitsPerFile, hits.count < maxHits {
                        let (snippet, snippetRange) = makeSnippet(String(line), matchRange: range, in: lower)
                        hits.append(Hit(url: url, relativePath: relative, line: lineNumber, snippet: snippet, matchRange: snippetRange, matchIndex: matchIndex))
                        fileHits += 1
                    } else {
                        truncated = true
                    }
                    matchIndex += 1
                    searchStart = range.upperBound
                }
            }
            if fileHits > 0 { fileCount += 1 }
        }
        return (hits, Summary(hits: hits.count, files: fileCount, truncated: truncated))
    }

    /// 일치 위치 앞뒤로 잘라 한 줄 스니펫을 만든다. 소문자화 문자열과 원본은 인덱스가 같다고 보고(ASCII·한글은 길이가 같다) 원본에서 자른다.
    nonisolated private static func makeSnippet(_ line: String, matchRange: Range<String.Index>, in lower: String) -> (String, Range<String.Index>) {
        let trimmedLine = line
        let start = lower.distance(from: lower.startIndex, to: matchRange.lowerBound)
        let length = lower.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
        guard trimmedLine.count >= start + length else {
            return (trimmedLine, trimmedLine.startIndex..<trimmedLine.startIndex)
        }
        let leading = 40
        let trailing = 90
        let from = max(0, start - leading)
        let to = min(trimmedLine.count, start + length + trailing)
        var snippet = String(trimmedLine.dropFirst(from).prefix(to - from))
        var matchStart = start - from
        if from > 0 { snippet = "…" + snippet; matchStart += 1 }
        if to < trimmedLine.count { snippet += "…" }
        let lowerBound = snippet.index(snippet.startIndex, offsetBy: min(matchStart, snippet.count))
        let upperBound = snippet.index(lowerBound, offsetBy: min(length, snippet.distance(from: lowerBound, to: snippet.endIndex)))
        return (snippet, lowerBound..<upperBound)
    }
}
