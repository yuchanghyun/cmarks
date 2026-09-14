import LayoutKit
import SwiftUI

/// 패인 트리를 평면으로 배치한다. 각 패인은 트리 구조와 무관하게 같은 뷰 정체성을 유지하므로 분할·닫기 때 웹뷰가 재생성되지 않는다.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cmarksWindowID) private var windowID

    var body: some View {
        let workspaceID = model.workspaceID(inWindow: windowID)
        GeometryReader { geometry in
            let size = geometry.size
            let frames = workspaceID.map { model.layoutFrames(in: CGRect(origin: .zero, size: size), workspaceID: $0) } ?? LayoutFrames(panes: [], dividers: [])
            ZStack(alignment: .topLeading) {
                ForEach(frames.panes, id: \.paneID) { frame in
                    PaneView(paneID: frame.paneID)
                        .frame(width: max(0, frame.rect.width), height: max(0, frame.rect.height))
                        .offset(x: frame.rect.minX, y: frame.rect.minY)
                }
                ForEach(frames.dividers) { divider in
                    DividerHandle(divider: divider)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: size, initial: true) { _, newSize in
                if let workspaceID { model.setViewportSize(newSize, workspaceID: workspaceID) }
            }
        }
    }
}
