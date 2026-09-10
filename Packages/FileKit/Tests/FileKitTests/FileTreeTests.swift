import Foundation
import Testing
@testable import FileKit

struct FileTreeTests {
    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmarks-tree-\(UUID().uuidString)")
        let fm = FileManager.default
        for dir in ["docs", "docs/sub", "node_modules/pkg", ".git", "src", "z-empty"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in ["README.md", "b.md", "a.md", "notes.txt", "docs/guide.md", "docs/sub/deep.MD", "docs/image.png", "node_modules/pkg/x.md", ".git/config.md", "src/main.swift", ".hidden.md", "file 10.md", "file 2.md"] {
            try Data("# x\n".utf8).write(to: root.appendingPathComponent(file))
        }
        return root
    }

    @Test func listsDirectoriesFirstWithNaturalSortAndFilters() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let nodes = try DirectoryLister.children(of: root)
        #expect(nodes.map(\.name) == ["docs", "src", "z-empty", "a.md", "b.md", "file 2.md", "file 10.md", "README.md"])
        #expect(nodes.first?.isDirectory == true)

        let hidden = try DirectoryLister.children(of: root, filter: FileFilter(showHidden: true))
        #expect(hidden.contains { $0.name == ".hidden.md" })
        #expect(!hidden.contains { $0.name == ".git" })
        #expect(!hidden.contains { $0.name == "node_modules" })
    }

    @Test func indexesMarkdownRecursivelySkippingIgnored() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        // 임시 디렉터리(/var → /private/var) 심볼릭 링크가 풀린 경로가 올 수 있어 realpath로 양쪽을 맞춘다.
        func real(_ url: URL) -> String {
            guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return url.path(percentEncoded: false) }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let rootPath = real(root) + "/"
        let files = FileIndexer.markdownFiles(under: root)
            .map { real($0).replacingOccurrences(of: rootPath, with: "") }
            .sorted()
        #expect(files == ["README.md", "a.md", "b.md", "docs/guide.md", "docs/sub/deep.MD", "file 10.md", "file 2.md"])
    }
}

struct FuzzyMatcherTests {
    @Test func matchesSubsequenceAndRanks() {
        let guide = FuzzyMatcher.match("gd", in: "docs/guide.md", fileNameStart: 5)
        let readme = FuzzyMatcher.match("gd", in: "README.md", fileNameStart: 0)
        #expect(guide != nil)
        #expect(readme == nil) // 'g' 없음

        let exact = FuzzyMatcher.match("guide", in: "docs/guide.md", fileNameStart: 5)!
        let spread = FuzzyMatcher.match("guide", in: "g/u/i/d/e.md", fileNameStart: 8)!
        #expect(exact.score > spread.score)
        #expect(exact.positions == [5, 6, 7, 8, 9])

        let boundary = FuzzyMatcher.match("ks", in: "kitchen-sink.md", fileNameStart: 0)!
        let middle = FuzzyMatcher.match("ks", in: "aakbbs.md", fileNameStart: 0)!
        #expect(boundary.score > middle.score)
        #expect(FuzzyMatcher.match("", in: "anything")?.score == 0)
        #expect(FuzzyMatcher.match("한글", in: "docs/한글 문서.md", fileNameStart: 5) != nil)
    }
}
