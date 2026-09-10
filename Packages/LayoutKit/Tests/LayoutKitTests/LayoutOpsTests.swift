import CoreGraphics
import Foundation
import Testing
@testable import LayoutKit

/// 시드 고정 난수. 실패를 재현할 수 있게 한다.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func approximately(_ actual: [Double]?, _ expected: [Double], tolerance: Double = 1e-9) -> Bool {
    guard let actual, actual.count == expected.count else { return false }
    return zip(actual, expected).allSatisfy { abs($0 - $1) <= tolerance }
}

struct LayoutOpsTests {
    let viewport = CGRect(x: 0, y: 0, width: 1200, height: 800)

    @Test func insertingRightCreatesHorizontalSplit() {
        let a = PaneID(), b = PaneID()
        let tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)
        guard case .split(let split) = tree else { Issue.record("expected split"); return }
        #expect(split.axis == .horizontal)
        #expect(split.children == [.leaf(a), .leaf(b)])
        #expect(split.fractions == [0.5, 0.5])
        #expect(tree.validate().isEmpty)
    }

    @Test func insertingSameAxisNestsSoClosingRestoresWidth() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)   // [a 0.5 | b 0.5]
        tree = tree.inserting(c, relativeTo: a, direction: .right)                     // [(a|c) 0.5 | b 0.5]
        guard case .split(let root) = tree, case .split(let inner) = root.children[0] else { Issue.record("expected nested split"); return }
        #expect(root.fractions == [0.5, 0.5])
        #expect(inner.children == [.leaf(a), .leaf(c)])
        #expect(tree.paneIDs == [a, c, b])

        // c를 닫으면 a가 원래 폭(0.5)으로 돌아온다
        let closed = tree.removing(c)!
        guard case .split(let after) = closed else { Issue.record("expected split"); return }
        #expect(after.children == [.leaf(a), .leaf(b)])
        #expect(after.fractions == [0.5, 0.5])
    }

    @Test func insertingOtherAxisNestsSplit() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)
        tree = tree.inserting(c, relativeTo: b, direction: .down)
        guard case .split(let outer) = tree, case .split(let inner) = outer.children[1] else { Issue.record("expected nested split"); return }
        #expect(inner.axis == .vertical)
        #expect(inner.children == [.leaf(b), .leaf(c)])
        #expect(tree.validate().isEmpty)
    }

    @Test func removingHoistsSingleChildAndRenormalizes() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)
        tree = tree.inserting(c, relativeTo: b, direction: .down) // [a | (b / c)]
        guard case .split(var root) = tree else { return }
        root.fractions = [0.3, 0.7]
        tree = .split(root)

        let withoutC = tree.removing(c)!
        guard case .split(let split) = withoutC else { Issue.record("expected split"); return }
        #expect(split.children == [.leaf(a), .leaf(b)])
        #expect(split.fractions == [0.3, 0.7])
        #expect(withoutC.removing(b) == .leaf(a))
        #expect(LayoutNode.leaf(a).removing(a) == nil)
    }

    @Test func layoutFramesAndDividers() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)
        tree = tree.inserting(c, relativeTo: b, direction: .down)
        let frames = tree.layout(in: CGRect(x: 0, y: 0, width: 1001, height: 601), dividerThickness: 1)
        #expect(frames.rect(of: a) == CGRect(x: 0, y: 0, width: 500, height: 601))
        #expect(frames.rect(of: b) == CGRect(x: 501, y: 0, width: 500, height: 300))
        #expect(frames.rect(of: c) == CGRect(x: 501, y: 301, width: 500, height: 300))
        #expect(frames.dividers.count == 2)
        #expect(frames.dividers[0].axis == .horizontal)
        #expect(frames.dividers[0].rect == CGRect(x: 500, y: 0, width: 1, height: 601))
        #expect(frames.dividers[1].splitLength == 601)
    }

    @Test func neighborsInGrid() {
        // a | b   위, c | d 아래
        let a = PaneID(), b = PaneID(), c = PaneID(), d = PaneID()
        var tree = LayoutNode.leaf(a).inserting(c, relativeTo: a, direction: .down)
        tree = tree.inserting(b, relativeTo: a, direction: .right)
        tree = tree.inserting(d, relativeTo: c, direction: .right)
        #expect(tree.neighbor(of: a, direction: .right, in: viewport) == b)
        #expect(tree.neighbor(of: a, direction: .down, in: viewport) == c)
        #expect(tree.neighbor(of: d, direction: .up, in: viewport) == b)
        #expect(tree.neighbor(of: d, direction: .left, in: viewport) == c)
        #expect(tree.neighbor(of: a, direction: .left, in: viewport) == nil)
        #expect(tree.neighbor(of: b, direction: .up, in: viewport) == nil)
    }

    @Test func resizingClampsToMinimum() {
        let a = PaneID(), b = PaneID()
        let tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)
        guard case .split(let split) = tree else { return }
        let grown = tree.resizing(split.id, dividerIndex: 0, from: [0.5, 0.5], by: 0.3, minimumFraction: 0.1)
        #expect(approximately(grown.split(withID: split.id)?.fractions, [0.8, 0.2]))
        let clamped = tree.resizing(split.id, dividerIndex: 0, from: [0.5, 0.5], by: 0.6, minimumFraction: 0.1)
        #expect(approximately(clamped.split(withID: split.id)?.fractions, [0.9, 0.1]))
        let equal = clamped.equalizing(split.id)
        #expect(equal.split(withID: split.id)?.fractions == [0.5, 0.5])
        #expect(equal.swapping(a, b).paneIDs == [b, a])
    }

    @Test func keyboardResizeGrowsAndShrinksNearestSplit() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = LayoutNode.leaf(a).inserting(b, relativeTo: a, direction: .right)
        tree = tree.inserting(c, relativeTo: b, direction: .down) // a | (b / c)
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
        guard case .split(let outer) = tree, case .split(let inner) = outer.children[1] else { return }

        // a를 오른쪽으로 100pt 키우면 바깥 split의 비율이 0.6/0.4
        let grown = tree.resizingLeaf(a, direction: .right, by: 100, in: rect, minimumSize: 50)
        #expect(approximately(grown.split(withID: outer.id)?.fractions, [0.6, 0.4]))
        // b(끝 패인 아님)를 아래로 60pt 키우면 안쪽 split 0.6/0.4
        let taller = tree.resizingLeaf(b, direction: .down, by: 60, in: rect, minimumSize: 50)
        #expect(approximately(taller.split(withID: inner.id)?.fractions, [0.6, 0.4]))
        // c(아래 끝)를 아래로 키우면 위 경계가 올라간다 → 0.4/0.6
        let cTaller = tree.resizingLeaf(c, direction: .down, by: 60, in: rect, minimumSize: 50)
        #expect(approximately(cTaller.split(withID: inner.id)?.fractions, [0.4, 0.6]))
        // b를 오른쪽으로 키우면 가로 축의 가장 가까운 조상(바깥 split)에서 b는 끝 패인이므로 왼쪽 경계가 왼쪽으로 → 0.4/0.6
        let bWider = tree.resizingLeaf(b, direction: .right, by: 100, in: rect, minimumSize: 50)
        #expect(approximately(bWider.split(withID: outer.id)?.fractions, [0.4, 0.6]))
        #expect(bWider.validate().isEmpty)
        #expect(tree.splitRects(in: rect)[inner.id]?.width == 499.5)
    }

    @Test func randomOperationsKeepInvariants() {
        var rng = SplitMix64(seed: 20260907)
        let root = PaneID()
        var tree = LayoutNode.leaf(root)
        var panes = [root]

        for step in 0..<1000 {
            let roll = Int(rng.next() % 100)
            let target = panes.randomElement(using: &rng)!
            switch roll {
            case 0..<45:
                let newPane = PaneID()
                tree = tree.inserting(newPane, relativeTo: target, direction: SplitDirection.allCases.randomElement(using: &rng)!)
                panes.append(newPane)
                #expect(tree.contains(newPane), "step \(step): inserted pane missing")
            case 45..<80 where panes.count > 1:
                tree = tree.removing(target)!
                panes.removeAll { $0 == target }
                #expect(!tree.contains(target), "step \(step): removed pane still present")
            case 80..<90:
                if let splitID = tree.splitIDs.randomElement(using: &rng), let split = tree.split(withID: splitID) {
                    let index = Int(rng.next() % UInt64(split.children.count - 1))
                    let delta = Double(rng.next() % 200) / 100 - 1
                    tree = tree.resizing(splitID, dividerIndex: index, from: split.fractions, by: delta, minimumFraction: 0.05)
                }
            case 90..<95:
                if let splitID = tree.splitIDs.randomElement(using: &rng) { tree = tree.equalizing(splitID) }
            default:
                let other = panes.randomElement(using: &rng)!
                tree = tree.swapping(target, other)
            }
            let problems = tree.validate()
            #expect(problems.isEmpty, "step \(step): \(problems)")
            #expect(Set(tree.paneIDs) == Set(panes), "step \(step): pane set mismatch")
            let frames = tree.layout(in: viewport)
            #expect(frames.panes.count == panes.count)
            for frame in frames.panes {
                let r = frame.rect
                let inside = r.width >= 0 && r.height >= 0
                    && r.minX >= viewport.minX - 0.01 && r.minY >= viewport.minY - 0.01
                    && r.maxX <= viewport.maxX + 0.01 && r.maxY <= viewport.maxY + 0.01
                #expect(inside, "step \(step): frame \(r) out of viewport")
            }
        }
    }
}
