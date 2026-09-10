import AppKit
import Foundation
import LayoutKit
import WebKit
@testable import cmarks

/// 조건이 참이 될 때까지 기다린다(기본 10초).
@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

/// 비동기 조건이 참이 될 때까지 기다린다.
@MainActor
func waitUntilAsync(timeout: Duration = .seconds(10), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

/// 저장소의 fixtures 폴더.
let repositoryFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

/// fixtures를 임시 폴더로 복사한다(상대 링크·이미지가 함께 있어야 한다).
func makeFixtureCopy() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cmarks-it-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: repositoryFixtures, to: dir)
    return dir
}

/// 사용자 상태를 건드리지 않는 AppModel.
@MainActor
func makeTestModel() throws -> (AppModel, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cmarks-model-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "cmarks.tests.\(UUID().uuidString)")!
    let model = AppModel(sessionStore: SessionStore(directory: dir), defaults: defaults)
    return (model, dir)
}

extension PaneViewer {
    /// 페이지 안에서 식(expression)을 평가한다.
    @MainActor
    func evaluate(_ expression: String) async throws -> Any? {
        try await webView.callAsyncJavaScript("return (\(expression));", contentWorld: .page)
    }
}

/// 링크 이동 요청을 기록한다.
@MainActor
final class NavigationCapture {
    var requests: [(DocumentRef, NavigationIntent)] = []
}
