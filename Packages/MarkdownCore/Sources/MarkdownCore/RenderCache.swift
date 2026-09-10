import Foundation

public struct RenderCacheKey: Hashable, Sendable {
    public var path: String
    public var modificationDate: Date?
    public var size: Int
    public var settings: RenderSettings

    public init(path: String, modificationDate: Date?, size: Int, settings: RenderSettings) {
        self.path = path
        self.modificationDate = modificationDate
        self.size = size
        self.settings = settings
    }
}

/// 바이트 상한이 있는 LRU 캐시. RenderPipeline 액터 안에서만 쓴다.
public struct RenderCache: Sendable {
    public let maxBytes: Int
    private var entries: [RenderCacheKey: RenderedDocument] = [:]
    private var order: [RenderCacheKey] = []
    private(set) var totalBytes = 0

    public init(maxBytes: Int = 50 << 20) {
        self.maxBytes = maxBytes
    }

    public var count: Int { entries.count }

    public mutating func value(for key: RenderCacheKey) -> RenderedDocument? {
        guard let value = entries[key] else { return nil }
        touch(key)
        return value
    }

    public mutating func insert(_ document: RenderedDocument, for key: RenderCacheKey) {
        remove(key)
        entries[key] = document
        order.append(key)
        totalBytes += document.pageHTML.utf8.count
        while totalBytes > maxBytes, let oldest = order.first {
            remove(oldest)
        }
    }

    public mutating func removeAll(path: String) {
        for key in order where key.path == path {
            remove(key)
        }
    }

    private mutating func remove(_ key: RenderCacheKey) {
        guard let removed = entries.removeValue(forKey: key) else { return }
        totalBytes -= removed.pageHTML.utf8.count
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: RenderCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
