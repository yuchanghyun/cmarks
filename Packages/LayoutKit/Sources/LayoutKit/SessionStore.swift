import Foundation

/// 워크스페이스·탭·스크롤을 JSON 하나로 저장한다(설계 문서 §4.8). 원자적으로 쓰고, 스키마 버전으로 이전 형식을 거른다.
/// 열려 있던 창 하나. 첫 항목이 기본 창이며 activeWorkspaceID와 같다.
public struct SessionWindow: Codable, Equatable, Sendable {
    public var workspaceID: UUID
    /// NSWindow.frameDescriptor. 창 복원은 앱이 직접 한다(AppKit 창 복원은 끈다).
    public var frame: String?
    public init(workspaceID: UUID, frame: String? = nil) {
        self.workspaceID = workspaceID
        self.frame = frame
    }
}

public struct Session: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var workspaces: [Workspace]
    public var activeWorkspaceID: UUID?
    /// 열려 있던 창들(1.3.0+). 없으면 창 하나.
    public var windows: [SessionWindow]?
    public var savedAt: Date

    public init(workspaces: [Workspace], activeWorkspaceID: UUID?, windows: [SessionWindow]? = nil, savedAt: Date = .now) {
        self.schemaVersion = Self.currentSchemaVersion
        self.workspaces = workspaces
        self.activeWorkspaceID = activeWorkspaceID
        self.windows = windows
        self.savedAt = savedAt
    }
}

public struct SessionStore: Sendable {
    public enum LoadError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    public let fileURL: URL

    public init(directory: URL, fileName: String = "session.json") {
        self.fileURL = directory.appending(path: fileName)
    }

    /// 기본 위치: ~/Library/Application Support/<appName>/session.json
    public static func standard(appName: String) -> SessionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return SessionStore(directory: base.appending(path: appName))
    }

    /// 파일이 없으면 nil. 손상됐거나 스키마가 맞지 않으면 throw.
    public func load() throws -> Session? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let probe = try decoder.decode(SchemaProbe.self, from: data)
        guard probe.schemaVersion == Session.currentSchemaVersion else { throw LoadError.unsupportedSchema(probe.schemaVersion) }
        return try decoder.decode(Session.self, from: data)
    }

    public func save(_ session: Session) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(session).write(to: fileURL, options: .atomic)
    }

    private struct SchemaProbe: Decodable {
        var schemaVersion: Int
    }
}
