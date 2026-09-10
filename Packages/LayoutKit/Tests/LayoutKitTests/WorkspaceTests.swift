import Foundation
import Testing
@testable import LayoutKit

struct WorkspaceTests {
    @Test func singleWorkspaceHasOnePaneAndOptionalTab() {
        let empty = Workspace.single()
        #expect(empty.panes.count == 1)
        #expect(empty.focusedPane?.tabs.isEmpty == true)
        #expect(empty.layout.paneIDs == [empty.focusedPaneID])

        let doc = DocumentRef(url: URL(fileURLWithPath: "/tmp/a.md"), fragment: "intro")
        let withDoc = Workspace.single(document: doc)
        #expect(withDoc.focusedPane?.activeTab?.document == doc)
        #expect(withDoc.focusedPane?.activeTab?.history == [doc])
    }

    @Test func codableRoundTrip() throws {
        var workspace = Workspace.single(name: "proj", rootURL: URL(fileURLWithPath: "/tmp/proj"), document: DocumentRef(url: URL(fileURLWithPath: "/tmp/proj/README.md")))
        workspace.isEphemeral = true
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(decoded == workspace)
    }

    @Test func containsAndRelativePath() {
        let ws = Workspace.single(name: "p", rootURL: URL(fileURLWithPath: "/tmp/proj"))
        #expect(ws.contains(URL(fileURLWithPath: "/tmp/proj/docs/a.md")))
        #expect(ws.contains(URL(fileURLWithPath: "/tmp/proj")))
        #expect(!ws.contains(URL(fileURLWithPath: "/tmp/project-b/a.md")))
        #expect(ws.relativePath(of: URL(fileURLWithPath: "/tmp/proj/docs/a.md")) == "docs/a.md")
        #expect(ws.relativePath(of: URL(fileURLWithPath: "/tmp/proj")) == "")
        #expect(ws.relativePath(of: URL(fileURLWithPath: "/etc/x.md")) == nil)
        #expect(Workspace.single().contains(URL(fileURLWithPath: "/tmp/a.md")) == false)
        #expect(ws.isEmpty)
    }

    @Test func decodesSessionWithoutSidebarField() throws {
        var ws = Workspace.single(name: "p")
        ws.sidebar = SidebarState(expandedDirectories: ["", "docs"])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ws)) as! [String: Any]
        json.removeValue(forKey: "sidebar")
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.sidebar == nil)
        #expect(decoded.id == ws.id)
    }

    @Test func updateReplacesPaneByID() {
        var workspace = Workspace.single()
        var pane = workspace.focusedPane!
        pane.tabs.append(Tab(document: DocumentRef(url: URL(fileURLWithPath: "/tmp/b.md"))))
        pane.activeTabID = pane.tabs.first?.id
        workspace.update(pane)
        #expect(workspace.panes.count == 1)
        #expect(workspace.focusedPane?.tabs.count == 1)
    }
}
