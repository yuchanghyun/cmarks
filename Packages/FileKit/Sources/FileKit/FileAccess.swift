import Foundation

/// 파일 한 번 읽기의 결과. 렌더 캐시 키(mtime, size)에 쓰인다.
public struct FileContents: Sendable {
    public var data: Data
    public var modificationDate: Date?
    public var size: Int

    public init(data: Data, modificationDate: Date?, size: Int) {
        self.data = data
        self.modificationDate = modificationDate
        self.size = size
    }
}

/// 파일 시스템 접근 경계(설계 문서 ADR-5).
/// v1은 샌드박스가 꺼져 있어 DirectFileAccess가 그대로 읽는다.
/// 샌드박스를 켤 때는 보안 범위 북마크를 다루는 구현을 이 프로토콜 뒤에 끼운다.
public protocol FileAccess: Sendable {
    func read(_ url: URL) throws -> Data
    func contents(_ url: URL) throws -> FileContents
    func exists(_ url: URL) -> Bool
}

public extension FileAccess {
    func contents(_ url: URL) throws -> FileContents {
        let data = try read(url)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return FileContents(data: data, modificationDate: values?.contentModificationDate, size: data.count)
    }
}

public struct DirectFileAccess: FileAccess {
    public init() {}

    /// 메모리 매핑은 쓰지 않는다. 라이브 리로드 중 파일이 잘리면 매핑된 메모리 접근이 크래시를 낸다.
    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
