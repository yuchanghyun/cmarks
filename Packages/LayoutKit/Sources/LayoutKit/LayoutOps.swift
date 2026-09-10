import CoreGraphics
import Foundation

public enum SplitDirection: String, Sendable, CaseIterable {
    case left, right, up, down

    public var axis: SplitAxis {
        switch self {
        case .left, .right: .horizontal
        case .up, .down: .vertical
        }
    }

    /// 새 패인이 대상 뒤(오른쪽/아래)에 오는지.
    public var insertsAfter: Bool {
        self == .right || self == .down
    }
}

public enum FocusDirection: String, Sendable, CaseIterable {
    case left, right, up, down
}

/// 배치 결과. 좌표는 위가 0인 화면 좌표.
public struct PaneFrame: Equatable, Sendable {
    public var paneID: PaneID
    public var rect: CGRect

    public init(paneID: PaneID, rect: CGRect) {
        self.paneID = paneID
        self.rect = rect
    }
}

public struct DividerFrame: Equatable, Sendable, Identifiable {
    public var splitID: UUID
    public var index: Int
    public var axis: SplitAxis
    public var rect: CGRect
    /// 분할 컨테이너의 축 방향 길이. 드래그 이동량을 비율로 바꿀 때 쓴다.
    public var splitLength: CGFloat

    public var id: String { "\(splitID.uuidString)-\(index)" }

    public init(splitID: UUID, index: Int, axis: SplitAxis, rect: CGRect, splitLength: CGFloat) {
        self.splitID = splitID
        self.index = index
        self.axis = axis
        self.rect = rect
        self.splitLength = splitLength
    }
}

public struct LayoutFrames: Equatable, Sendable {
    public var panes: [PaneFrame]
    public var dividers: [DividerFrame]

    public init(panes: [PaneFrame], dividers: [DividerFrame]) {
        self.panes = panes
        self.dividers = dividers
    }

    public func rect(of pane: PaneID) -> CGRect? {
        panes.first { $0.paneID == pane }?.rect
    }
}

/// 패인 트리 연산(PLAN.md §4.2 표). 모두 순수 함수이며 새 트리를 돌려준다.
public extension LayoutNode {
    func contains(_ pane: PaneID) -> Bool {
        paneIDs.contains(pane)
    }

    var splitIDs: [UUID] {
        switch self {
        case .leaf: []
        case .split(let split): [split.id] + split.children.flatMap(\.splitIDs)
        }
    }

    /// 대상 패인 옆에 새 패인을 넣는다. 대상 leaf를 2-자식 split(0.5/0.5)으로 바꾼다.
    /// 부모 축이 같아도 형제로 끼우지 않고 중첩한다. 그래야 새 패인을 닫았을 때 대상이 정확히 이전 크기로 돌아온다
    /// (형제로 끼우면 남은 비율이 재정규화되어 대상이 작아진 채 남는다).
    func inserting(_ newPane: PaneID, relativeTo target: PaneID, direction: SplitDirection) -> LayoutNode {
        switch self {
        case .leaf(let id):
            guard id == target else { return self }
            let children: [LayoutNode] = direction.insertsAfter ? [.leaf(id), .leaf(newPane)] : [.leaf(newPane), .leaf(id)]
            return .split(SplitNode(axis: direction.axis, children: children, fractions: [0.5, 0.5]))

        case .split(var split):
            split.children = split.children.map { $0.inserting(newPane, relativeTo: target, direction: direction) }
            return .split(split)
        }
    }

    /// 패인을 제거한다. 자식이 하나 남은 split은 그 자식으로 승격되고, 비율은 다시 정규화된다. 마지막 leaf를 지우면 nil.
    func removing(_ pane: PaneID) -> LayoutNode? {
        switch self {
        case .leaf(let id):
            return id == pane ? nil : self

        case .split(var split):
            var children: [LayoutNode] = []
            var fractions: [Double] = []
            for (child, fraction) in zip(split.children, split.fractions) {
                if let kept = child.removing(pane) {
                    children.append(kept)
                    fractions.append(fraction)
                }
            }
            if children.isEmpty { return nil }
            if children.count == 1 { return children[0] }
            let total = fractions.reduce(0, +)
            split.children = children
            split.fractions = fractions.map { $0 / total }
            return .split(split)
        }
    }

    /// 두 leaf를 맞바꾼다.
    func swapping(_ a: PaneID, _ b: PaneID) -> LayoutNode {
        switch self {
        case .leaf(let id):
            if id == a { return .leaf(b) }
            if id == b { return .leaf(a) }
            return self
        case .split(var split):
            split.children = split.children.map { $0.swapping(a, b) }
            return .split(split)
        }
    }

    /// 특정 split의 비율을 바꾼다. 개수가 맞지 않으면 무시한다.
    func replacingFractions(of splitID: UUID, with fractions: [Double]) -> LayoutNode {
        updatingSplit(splitID) { split in
            guard fractions.count == split.children.count else { return }
            split.fractions = fractions
        }
    }

    func equalizing(_ splitID: UUID) -> LayoutNode {
        updatingSplit(splitID) { split in
            split.fractions = Array(repeating: 1.0 / Double(split.children.count), count: split.children.count)
        }
    }

    /// 디바이더 `index`(children[index]와 [index+1] 사이)를 비율 `delta`만큼 옮긴다. 양쪽 모두 `minimumFraction` 이상을 유지한다.
    func resizing(_ splitID: UUID, dividerIndex index: Int, from startFractions: [Double], by delta: Double, minimumFraction: Double) -> LayoutNode {
        updatingSplit(splitID) { split in
            guard startFractions.count == split.children.count, index >= 0, index + 1 < startFractions.count else { return }
            var fractions = startFractions
            let pair = fractions[index] + fractions[index + 1]
            let minimum = min(minimumFraction, pair / 2)
            let first = min(max(fractions[index] + delta, minimum), pair - minimum)
            fractions[index] = first
            fractions[index + 1] = pair - first
            split.fractions = fractions
        }
    }

    func split(withID splitID: UUID) -> SplitNode? {
        switch self {
        case .leaf: nil
        case .split(let split):
            split.id == splitID ? split : split.children.lazy.compactMap { $0.split(withID: splitID) }.first
        }
    }

    private func updatingSplit(_ splitID: UUID, _ mutate: (inout SplitNode) -> Void) -> LayoutNode {
        switch self {
        case .leaf:
            return self
        case .split(var split):
            if split.id == splitID {
                mutate(&split)
            } else {
                split.children = split.children.map { $0.updatingSplit(splitID, mutate) }
            }
            return .split(split)
        }
    }

    // MARK: 배치

    /// 트리를 rect 안에 배치한다. 디바이더는 자식 사이에 `dividerThickness` 만큼 자리를 차지한다.
    func layout(in rect: CGRect, dividerThickness: CGFloat = 1) -> LayoutFrames {
        var frames = LayoutFrames(panes: [], dividers: [])
        walk(self, rect, dividerThickness, &frames)
        return frames
    }

    private func walk(_ node: LayoutNode, _ rect: CGRect, _ thickness: CGFloat, _ frames: inout LayoutFrames) {
        switch node {
        case .leaf(let id):
            frames.panes.append(PaneFrame(paneID: id, rect: rect))
        case .split(let split):
            let horizontal = split.axis == .horizontal
            let length = horizontal ? rect.width : rect.height
            let available = max(0, length - thickness * CGFloat(split.children.count - 1))
            var offset: CGFloat = 0
            // 디바이더가 들어갈 자리가 없을 만큼 좁으면(극단적으로 많은 분할) 부모 rect 안으로 잘라 넣는다.
            func clamp(_ r: CGRect) -> CGRect {
                let clipped = r.intersection(rect)
                if clipped.isNull {
                    return CGRect(x: min(max(r.minX, rect.minX), rect.maxX), y: min(max(r.minY, rect.minY), rect.maxY), width: 0, height: 0)
                }
                return clipped
            }
            for (index, (child, fraction)) in zip(split.children, split.fractions).enumerated() {
                let isLast = index == split.children.count - 1
                let size = isLast ? max(0, length - offset) : available * CGFloat(fraction)
                let childRect = horizontal
                    ? CGRect(x: rect.minX + offset, y: rect.minY, width: size, height: rect.height)
                    : CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: size)
                walk(child, clamp(childRect), thickness, &frames)
                offset += size
                if !isLast {
                    let dividerRect = horizontal
                        ? CGRect(x: rect.minX + offset, y: rect.minY, width: thickness, height: rect.height)
                        : CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: thickness)
                    frames.dividers.append(DividerFrame(splitID: split.id, index: index, axis: split.axis, rect: clamp(dividerRect), splitLength: length))
                    offset += thickness
                }
            }
        }
    }

    /// 방향으로 가장 가까운 이웃 패인. 직교축으로 겹치는 후보 중 가장 가깝고, 같으면 겹침이 큰 것.
    func neighbor(of pane: PaneID, direction: FocusDirection, in rect: CGRect) -> PaneID? {
        let frames = layout(in: rect, dividerThickness: 0)
        guard let origin = frames.rect(of: pane) else { return nil }
        let epsilon: CGFloat = 0.5

        var best: (id: PaneID, distance: CGFloat, overlap: CGFloat)?
        for frame in frames.panes where frame.paneID != pane {
            let r = frame.rect
            let distance: CGFloat
            let overlap: CGFloat
            switch direction {
            case .right:
                guard r.minX >= origin.maxX - epsilon else { continue }
                distance = r.minX - origin.maxX
                overlap = verticalOverlap(origin, r)
            case .left:
                guard r.maxX <= origin.minX + epsilon else { continue }
                distance = origin.minX - r.maxX
                overlap = verticalOverlap(origin, r)
            case .down:
                guard r.minY >= origin.maxY - epsilon else { continue }
                distance = r.minY - origin.maxY
                overlap = horizontalOverlap(origin, r)
            case .up:
                guard r.maxY <= origin.minY + epsilon else { continue }
                distance = origin.minY - r.maxY
                overlap = horizontalOverlap(origin, r)
            }
            guard overlap > 0 else { continue }
            if let current = best {
                if distance < current.distance - epsilon || (abs(distance - current.distance) <= epsilon && overlap > current.overlap) {
                    best = (frame.paneID, distance, overlap)
                }
            } else {
                best = (frame.paneID, distance, overlap)
            }
        }
        return best?.id
    }

    private func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    private func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    }

    // MARK: 키보드 크기 조정

    /// 패인을 방향으로 `pixels`만큼 키우거나(right/down) 줄인다(left/up). 그 축의 가장 가까운 분할을 조정한다.
    /// 오른쪽/아래 끝 패인은 반대편 경계를 움직여 같은 효과를 낸다.
    func resizingLeaf(_ pane: PaneID, direction: FocusDirection, by pixels: CGFloat, in rect: CGRect, minimumSize: CGFloat) -> LayoutNode {
        let axis: SplitAxis = (direction == .left || direction == .right) ? .horizontal : .vertical
        let grow = direction == .right || direction == .down
        guard let (split, childIndex) = nearestAncestorSplit(of: pane, axis: axis),
              let splitRect = splitRects(in: rect)[split.id] else { return self }
        let length = axis == .horizontal ? splitRect.width : splitRect.height
        guard length > 0 else { return self }
        let fraction = Double(pixels / length)
        let minimum = Double(minimumSize / length)
        let lastIndex = split.children.count - 1
        if childIndex < lastIndex {
            // 오른쪽/아래 경계를 움직인다
            return resizing(split.id, dividerIndex: childIndex, from: split.fractions, by: grow ? fraction : -fraction, minimumFraction: minimum)
        }
        // 끝 패인: 왼쫽/위 경계를 반대로 움직인다
        return resizing(split.id, dividerIndex: childIndex - 1, from: split.fractions, by: grow ? -fraction : fraction, minimumFraction: minimum)
    }

    /// 패인을 담은 가장 가까운(안쪽) 조상 split 중 축이 같은 것과, 그 split에서 패인이 속한 자식 인덱스.
    func nearestAncestorSplit(of pane: PaneID, axis: SplitAxis) -> (SplitNode, Int)? {
        guard case .split(let split) = self else { return nil }
        guard let index = split.children.firstIndex(where: { $0.contains(pane) }) else { return nil }
        if let deeper = split.children[index].nearestAncestorSplit(of: pane, axis: axis) { return deeper }
        return split.axis == axis ? (split, index) : nil
    }

    /// 각 split이 차지하는 rect.
    func splitRects(in rect: CGRect, dividerThickness: CGFloat = 1) -> [UUID: CGRect] {
        var result: [UUID: CGRect] = [:]
        func walk(_ node: LayoutNode, _ rect: CGRect) {
            guard case .split(let split) = node else { return }
            result[split.id] = rect
            let frames = LayoutNode.split(split).layout(in: rect, dividerThickness: dividerThickness)
            for child in split.children {
                let ids = child.paneIDs
                let rects = frames.panes.filter { ids.contains($0.paneID) }.map(\.rect)
                guard let first = rects.first else { continue }
                walk(child, rects.dropFirst().reduce(first) { $0.union($1) })
            }
        }
        walk(self, rect)
        return result
    }

    // MARK: 불변식

    /// 위반 사항 목록. 비어 있으면 정상.
    func validate() -> [String] {
        var problems: [String] = []
        var seen = Set<PaneID>()
        for id in paneIDs {
            if !seen.insert(id).inserted { problems.append("duplicate pane \(id.raw)") }
        }
        func check(_ node: LayoutNode, depth: Int) {
            guard case .split(let split) = node else { return }
            if split.children.count < 2 { problems.append("split \(split.id) has \(split.children.count) children") }
            if split.fractions.count != split.children.count { problems.append("split \(split.id) fractions/children mismatch") }
            if abs(split.fractions.reduce(0, +) - 1) > 1e-6 { problems.append("split \(split.id) fractions sum \(split.fractions.reduce(0, +))") }
            if split.fractions.contains(where: { $0 <= 0 }) { problems.append("split \(split.id) has non-positive fraction") }
            split.children.forEach { check($0, depth: depth + 1) }
        }
        check(self, depth: 0)
        return problems
    }
}
