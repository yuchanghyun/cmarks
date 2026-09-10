import Foundation

/// 패인 식별자. 탭/웹뷰/포커스가 모두 이 값으로 패인을 가리킨다.
public struct PaneID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
}

/// 분할 축. horizontal은 자식이 좌우로(⌘D), vertical은 상하로(⌘⇧D) 놓인다.
public enum SplitAxis: String, Codable, Sendable {
    case horizontal
    case vertical
}

/// 패인 트리(설계 문서 §4.2). leaf가 패인, split이 분할 컨테이너.
public indirect enum LayoutNode: Codable, Equatable, Sendable {
    case leaf(PaneID)
    case split(SplitNode)
}

public struct SplitNode: Codable, Equatable, Sendable {
    public var id: UUID
    public var axis: SplitAxis
    /// 항상 2개 이상.
    public var children: [LayoutNode]
    /// children과 같은 개수, 합 1.0.
    public var fractions: [Double]

    public init(id: UUID = UUID(), axis: SplitAxis, children: [LayoutNode], fractions: [Double]) {
        self.id = id
        self.axis = axis
        self.children = children
        self.fractions = fractions
    }
}

public extension LayoutNode {
    /// 트리의 모든 패인을 깊이 우선(왼쪽/위 먼저) 순서로 돌려준다.
    var paneIDs: [PaneID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(let split):
            return split.children.flatMap(\.paneIDs)
        }
    }
}
