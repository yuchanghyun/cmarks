import Foundation

/// 파일 트리의 한 줄. id는 절대 경로.
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    public var isSymlink: Bool

    public var id: String { url.path(percentEncoded: false) }

    public init(url: URL, name: String, isDirectory: Bool, isSymlink: Bool = false) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }
}

/// 트리·인덱스 공통 필터(설계 문서 §4.7 무시 패턴, §5.3 파일 설정).
public struct FileFilter: Sendable, Hashable {
    public var markdownExtensions: Set<String>
    public var ignoredDirectoryNames: Set<String>
    public var showHidden: Bool
    public var followSymlinks: Bool

    public init(
        markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdtxt", "mdtext", "mdx", "qmd", "rmd"],
        ignoredDirectoryNames: Set<String> = [".git", "node_modules", ".build", "DerivedData", ".svn", ".hg", "__pycache__", ".venv", "Pods"],
        showHidden: Bool = false,
        followSymlinks: Bool = false
    ) {
        self.markdownExtensions = markdownExtensions
        self.ignoredDirectoryNames = ignoredDirectoryNames
        self.showHidden = showHidden
        self.followSymlinks = followSymlinks
    }

    public static let `default` = FileFilter()

    public func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    public func isIgnoredDirectory(named name: String) -> Bool {
        ignoredDirectoryNames.contains(name)
    }
}

/// 디렉터리 한 단계를 읽는다. 폴더 먼저, 그다음 자연 정렬. 마크다운 파일만 보인다.
public enum DirectoryLister {
    public static func children(of directory: URL, filter: FileFilter = .default) throws -> [FileTreeNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .nameKey]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !filter.showHidden { options.insert(.skipsHiddenFiles) }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: options)

        var nodes: [FileTreeNode] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: keys)
            let isSymlink = values?.isSymbolicLink ?? false
            var isDirectory = values?.isDirectory ?? false
            if isSymlink {
                guard filter.followSymlinks else { continue }
                let resolved = url.resolvingSymlinksInPath()
                isDirectory = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            let name = values?.name ?? url.lastPathComponent
            if isDirectory {
                guard !filter.isIgnoredDirectory(named: name) else { continue }
            } else {
                guard filter.isMarkdown(url) else { continue }
            }
            nodes.append(FileTreeNode(url: url, name: name, isDirectory: isDirectory, isSymlink: isSymlink))
        }
        return nodes.sorted(by: Self.isOrderedBefore)
    }

    static func isOrderedBefore(_ a: FileTreeNode, _ b: FileTreeNode) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}

/// 워크스페이스 전체의 마크다운 파일 목록(빠른 열기 색인).
public enum FileIndexer {
    public static func markdownFiles(under root: URL, filter: FileFilter = .default, limit: Int = 200_000) -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !filter.showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isSymbolicLinkKey], options: options) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .nameKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true, !filter.followSymlinks {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true {
                if filter.isIgnoredDirectory(named: values?.name ?? url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if filter.isMarkdown(url) {
                results.append(url)
                if results.count >= limit { break }
            }
        }
        return results
    }
}
