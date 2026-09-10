import Foundation
import Testing
@testable import LayoutKit

struct TabHistoryTests {
    let a = DocumentRef(url: URL(fileURLWithPath: "/tmp/a.md"))
    let b = DocumentRef(url: URL(fileURLWithPath: "/tmp/b.md"), fragment: "sec")
    let c = DocumentRef(url: URL(fileURLWithPath: "/tmp/c.md"))

    @Test func navigateBackForward() {
        var tab = Tab(document: a)
        #expect(!tab.canGoBack && !tab.canGoForward)

        tab.navigate(to: b)
        tab.navigate(to: c)
        #expect(tab.history == [a, b, c])
        #expect(tab.canGoBack && !tab.canGoForward)

        #expect(tab.goBack() == b)
        #expect(tab.document == b)
        #expect(tab.goBack() == a)
        #expect(tab.goBack() == nil)
        #expect(tab.goForward() == b)
        #expect(tab.canGoForward)
    }

    @Test func navigatingFromMiddleDropsForwardEntries() {
        var tab = Tab(document: a)
        tab.navigate(to: b)
        tab.navigate(to: c)
        tab.goBack()
        tab.goBack()
        tab.navigate(to: c)
        #expect(tab.history == [a, c])
        #expect(tab.historyIndex == 1)
        #expect(!tab.canGoForward)
    }
}
