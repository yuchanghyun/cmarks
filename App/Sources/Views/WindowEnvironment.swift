import SwiftUI

/// 이 뷰 트리가 속한 창. 창마다 다른 워크스페이스를 보여 준다(AppModel.windowSlots).
private struct CmarksWindowIDKey: EnvironmentKey {
    static let defaultValue = AppModel.primaryWindowID
}

extension EnvironmentValues {
    var cmarksWindowID: UUID {
        get { self[CmarksWindowIDKey.self] }
        set { self[CmarksWindowIDKey.self] = newValue }
    }
}
