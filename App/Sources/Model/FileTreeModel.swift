import FileKit
import Foundation
import OSLog

/// 사이드바 파일 트리. 펼친 디렉터리만 읽고, FSEvents로 바뀐 디렉터리만 다시 읽는다(설계 문서 §4.7).
@MainActor
@Observable
final class FileTreeModel {
    let root: URL
    var filter: FileFilter {
        didSet { if filter != oldValue { reloadLoaded() } }
    }
    /// 루트 기준 상대 경로("" = 루트) → 자식 노드. 아직 안 읽은 디렉터리는 키가 없다.
    private(set) var children: [String: [FileTreeNode]] = [:]
    private(set) var expanded: Set<String>
    /// 현재 활성 문서. 트리에서 강조된다.
    var highlightedURL: URL?
    /// 마지막으로 클릭한 행(파일 또는 폴더)의 상대 경로.
    var selectedPath: String?
    var onExpandedChange: ((Set<String>) -> Void)?

    private let realRoot: String
    private var watcher: DirectoryWatcher?
    private var pendingReloads: Set<String> = []
    private var reloadTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "tree")

    init(root: URL, filter: FileFilter, expanded: Set<String>) {
        self.root = root.standardizedFileURL
        self.filter = filter
        self.expanded = expanded.union([""])
        self.realRoot = Self.realPath(self.root.path(percentEncoded: false))
        for directory in self.expanded { load(directory) }
        watcher = DirectoryWatcher(url: self.root) { [weak self] paths in
            Task { @MainActor [weak self] in self?.handleChanges(paths) }
        }
    }

    // MARK: 읽기

    func nodes(in relative: String) -> [FileTreeNode]? {
        children[relative]
    }

    func relativePath(of node: FileTreeNode) -> String {
        relativePath(of: node.url) ?? node.name
    }

    func relativePath(of url: URL) -> String? {
        let path = Self.realPath(url.path(percentEncoded: false))
        if path == realRoot { return "" }
        guard path.hasPrefix(realRoot + "/") else { return nil }
        return String(path.dropFirst(realRoot.count + 1))
    }

    func isExpanded(_ node: FileTreeNode) -> Bool {
        expanded.contains(relativePath(of: node))
    }

    // MARK: 조작

    func setExpanded(_ node: FileTreeNode, _ value: Bool) {
        let relative = relativePath(of: node)
        if value {
            expanded.insert(relative)
            load(relative)
        } else {
            expanded.remove(relative)
        }
        onExpandedChange?(expanded)
    }

    /// 파일의 상위 폴더를 모두 펼치고 강조한다(활성 탭 ↔ 트리 동기화).
    func reveal(_ fileURL: URL) {
        highlightedURL = fileURL.standardizedFileURL
        guard let relative = relativePath(of: fileURL) else { return }
        var components = relative.split(separator: "/").map(String.init)
        components.removeLast()
        var path = ""
        var changed = false
        for component in components {
            path = path.isEmpty ? component : path + "/" + component
            if !expanded.contains(path) {
                expanded.insert(path)
                changed = true
            }
            load(path)
        }
        if changed { onExpandedChange?(expanded) }
    }

    func load(_ relative: String) {
        guard children[relative] == nil else { return }
        children[relative] = []
        reload(relative)
    }

    private func reload(_ relative: String) {
        let url = relative.isEmpty ? root : root.appending(path: relative)
        let filter = self.filter
        Task.detached(priority: .userInitiated) { [weak self] in
            let nodes = (try? DirectoryLister.children(of: url, filter: filter)) ?? []
            await self?.apply(nodes, for: relative)
        }
    }

    private func apply(_ nodes: [FileTreeNode], for relative: String) {
        children[relative] = nodes
    }

    private func reloadLoaded() {
        for relative in children.keys { reload(relative) }
    }

    // MARK: FSEvents

    private func handleChanges(_ paths: [String]) {
        for path in paths {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            let directoryPath = (exists && isDirectory.boolValue) ? path : (path as NSString).deletingLastPathComponent
            guard let relative = relativePath(of: URL(fileURLWithPath: directoryPath)) else { continue }
            // 바뀐 디렉터리와 그 부모(이름 변경·삭제는 부모 목록이 달라진다)
            pendingReloads.insert(relative)
            if !relative.isEmpty {
                pendingReloads.insert((relative as NSString).deletingLastPathComponent)
            }
        }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.flushReloads()
        }
    }

    private func flushReloads() {
        let targets = pendingReloads
        pendingReloads.removeAll()
        for relative in targets where children[relative] != nil {
            reload(relative)
        }
    }

    nonisolated static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
