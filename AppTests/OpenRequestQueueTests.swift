import Foundation
import Testing
@testable import cmarks

@MainActor
struct OpenRequestQueueTests {
    @Test func keepsFileURLsAndResolvesDeepLinks() {
        let queue = OpenRequestQueue()
        queue.enqueue([
            URL(fileURLWithPath: "/tmp/a.md"),
            URL(string: "https://example.com/x.md")!,
            URL(string: "cmarks://open?path=/tmp/b.md")!,
            URL(string: "cmarks://open")!,
        ])
        #expect(queue.pending.map(\.lastPathComponent) == ["a.md", "b.md"])
        #expect(queue.drain().count == 2)
        #expect(queue.pending.isEmpty)
    }
}
