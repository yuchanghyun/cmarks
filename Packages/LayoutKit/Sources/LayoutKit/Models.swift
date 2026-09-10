import Foundation

/// 문서 참조: 파일 URL + 선택적 앵커(#fragment).
public struct DocumentRef: Hashable, Codable, Sendable {
    public var url: URL
    public var fragment: String?

    public init(url: URL, fragment: String? = nil) {
        self.url = url
        self.fragment = fragment
    }
}

/// 패인 안의 탭 하나 = 문서 하나(설계 문서 §4.2).
public struct Tab: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var document: DocumentRef
    /// 단일 클릭 미리보기 탭. 다음 단일 클릭이 내용을 교체한다.
    public var isPreview: Bool
    public var isPinned: Bool
    /// 탭 안에서의 링크 이동 히스토리와 현재 위치.
    public var history: [DocumentRef]
    public var historyIndex: Int
    public var scrollY: Double
    public var zoom: Double

    public init(id: UUID = UUID(), document: DocumentRef, isPreview: Bool = false, isPinned: Bool = false, zoom: Double = 1.0) {
        self.id = id
        self.document = document
        self.isPreview = isPreview
        self.isPinned = isPinned
        self.history = [document]
        self.historyIndex = 0
        self.scrollY = 0
        self.zoom = zoom
    }
}

public struct Pane: Identifiable, Codable, Equatable, Sendable {
    public let id: PaneID
    public var tabs: [Tab]
    public var activeTabID: UUID?

    public init(id: PaneID = PaneID(), tabs: [Tab] = [], activeTabID: UUID? = nil) {
        self.id = id
        self.tabs = tabs
        self.activeTabID = activeTabID ?? tabs.first?.id
    }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }
}

/// 사이드바 UI 상태. 세션에 함께 저장된다.
public struct SidebarState: Codable, Equatable, Sendable {
    /// 루트 기준 상대 경로. 루트 자신은 "".
    public var expandedDirectories: Set<String>

    public init(expandedDirectories: Set<String> = [""]) {
        self.expandedDirectories = expandedDirectories
    }
}

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// nil이면 느슨한 파일 모음.
    public var rootURL: URL?
    public var layout: LayoutNode
    public var panes: [Pane]
    public var focusedPaneID: PaneID
    /// 패인 확대 토글. 트리는 그대로 두고 이 패인만 그린다.
    public var zoomedPaneID: PaneID?
    /// Finder에서 파일을 열어 생긴 임시 워크스페이스.
    public var isEphemeral: Bool
    public var lastActiveAt: Date
    /// 없으면(이전 세션 파일) 기본값으로 시작한다.
    public var sidebar: SidebarState?
    /// 최근에 포커스한 순서(앞이 최근). 패인을 닫을 때 다음 포커스를 정한다.
    public var focusHistory: [PaneID]?
    /// 최근에 닫은 탭(앞이 최근, 최대 20). ⌘⇧T로 되살린다.
    public var recentlyClosedTabs: [Tab]?

    public init(
        id: UUID = UUID(),
        name: String,
        rootURL: URL? = nil,
        layout: LayoutNode,
        panes: [Pane],
        focusedPaneID: PaneID,
        zoomedPaneID: PaneID? = nil,
        isEphemeral: Bool = false,
        lastActiveAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.layout = layout
        self.panes = panes
        self.focusedPaneID = focusedPaneID
        self.zoomedPaneID = zoomedPaneID
        self.isEphemeral = isEphemeral
        self.lastActiveAt = lastActiveAt
    }

    /// 루트 폴더 아래의 파일인지.
    public func contains(_ url: URL) -> Bool {
        guard let rootURL else { return false }
        let root = rootURL.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// 루트 기준 상대 경로. 루트 밖이면 nil.
    public func relativePath(of url: URL) -> String? {
        guard let rootURL, contains(url) else { return nil }
        let root = rootURL.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if path == root { return "" }
        return String(path.dropFirst(root.count + (root.hasSuffix("/") ? 0 : 1)))
    }

    /// 모든 패인에 탭이 하나도 없는지.
    public var isEmpty: Bool {
        panes.allSatisfy { $0.tabs.isEmpty }
    }

    /// 패인 하나짜리 워크스페이스. 문서가 있으면 탭 하나로 시작한다.
    public static func single(name: String = "Untitled", rootURL: URL? = nil, document: DocumentRef? = nil) -> Workspace {
        let pane = Pane(tabs: document.map { [Tab(document: $0)] } ?? [])
        var workspace = Workspace(name: name, rootURL: rootURL, layout: .leaf(pane.id), panes: [pane], focusedPaneID: pane.id)
        workspace.focusHistory = [pane.id]
        return workspace
    }

    public func pane(_ id: PaneID) -> Pane? {
        panes.first { $0.id == id }
    }

    public var focusedPane: Pane? {
        pane(focusedPaneID)
    }

    public mutating func update(_ pane: Pane) {
        if let index = panes.firstIndex(where: { $0.id == pane.id }) {
            panes[index] = pane
        } else {
            panes.append(pane)
        }
    }
}
