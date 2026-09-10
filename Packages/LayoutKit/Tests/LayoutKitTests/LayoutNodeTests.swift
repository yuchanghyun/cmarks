import Foundation
import Testing
@testable import LayoutKit

struct LayoutNodeTests {
    @Test func codableRoundTripPreservesTreeAndOrder() throws {
        let a = PaneID(), b = PaneID(), c = PaneID()
        let tree = LayoutNode.split(SplitNode(
            axis: .horizontal,
            children: [
                .leaf(a),
                .split(SplitNode(axis: .vertical, children: [.leaf(b), .leaf(c)], fractions: [0.5, 0.5])),
            ],
            fractions: [0.6, 0.4]
        ))

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(LayoutNode.self, from: data)

        #expect(decoded == tree)
        #expect(decoded.paneIDs == [a, b, c])
    }
}
