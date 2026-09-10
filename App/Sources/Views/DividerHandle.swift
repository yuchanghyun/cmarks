import AppKit
import LayoutKit
import SwiftUI

/// 분할선. 옆의 WKWebView(AppKit)가 마우스 이벤트를 먼저 가져가므로 SwiftUI 제스처로는 드래그가 되지 않았다.
/// 그래서 NSView로 만들고, 레이아웃에서 7pt 폭을 웹뷰가 덮지 않는 전용 자리로 비워 둔다. 가운데 1pt 선을 그리고 더블클릭은 균등 분할.
struct DividerHandle: View {
    let divider: DividerFrame

    var body: some View {
        let rect = divider.rect
        DividerSurface(divider: divider)
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .offset(x: rect.minX, y: rect.minY)
            .zIndex(1)
    }
}

private struct DividerSurface: NSViewRepresentable {
    let divider: DividerFrame
    @Environment(AppModel.self) private var model

    private let minimumPaneSize: CGFloat = 120

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> DividerNSView {
        let view = DividerNSView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: DividerNSView, context: Context) {
        configure(view, coordinator: context.coordinator)
    }

    private func configure(_ view: DividerNSView, coordinator: Coordinator) {
        let divider = self.divider
        let model = self.model
        let minimum = minimumPaneSize
        view.axis = divider.axis
        view.onDragBegan = { coordinator.startFractions = model.split(withID: divider.splitID)?.fractions }
        view.onDragChanged = { translation in
            guard let start = coordinator.startFractions, divider.splitLength > 0 else { return }
            model.resize(
                divider.splitID,
                dividerIndex: divider.index,
                startFractions: start,
                delta: Double(translation / divider.splitLength),
                minimumFraction: Double(minimum / divider.splitLength)
            )
        }
        view.onDragEnded = { coordinator.startFractions = nil }
        view.onDoubleClick = { model.equalize(divider.splitID) }
    }

    final class Coordinator {
        var startFractions: [Double]?
    }
}

final class DividerNSView: NSView {
    var axis: SplitAxis = .horizontal {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var dragOrigin: NSPoint?
    private var hovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    private var cursor: NSCursor {
        axis == .horizontal ? .resizeLeftRight : .resizeUpDown
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        dragOrigin = event.locationInWindow
        onDragBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = event.locationInWindow
        // 창 좌표는 y가 위로 증가한다. 레이아웃은 위가 0이므로 아래로 끌면 양수가 되게 뒤집는다.
        let translation = axis == .horizontal ? point.x - origin.x : origin.y - point.y
        onDragChanged?(translation)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        onDragEnded?()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let active = hovered || dragOrigin != nil
        (active ? NSColor.controlAccentColor : NSColor.separatorColor).setFill()
        let line = axis == .horizontal
            ? NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height)
            : NSRect(x: bounds.minX, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        line.fill()
    }
}
