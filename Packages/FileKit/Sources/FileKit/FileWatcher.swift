import Foundation

/// 파일 하나의 변경을 감시한다(PLAN.md §4.7).
/// 편집기의 원자적 저장(임시 파일 → rename)이나 백업 저장(원본 rename → 새 파일)으로 vnode가 바뀌어도
/// 같은 경로를 다시 열어 감시를 이어 간다. 이벤트는 내부 직렬 큐에서 전달된다.
public final class FileWatcher: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        /// 내용이 바뀌었거나(쓰기·확장·속성), 사라졌던 파일이 돌아왔다.
        case changed
        /// 경로에 파일이 없다. 다시 나타나면 `.changed`가 온다.
        case disappeared
    }

    public typealias Handler = @Sendable (Event) -> Void

    private let path: String
    private let debounceMS: Int
    private let handler: Handler
    private let queue = DispatchQueue(label: "cmarks.FileWatcher", qos: .utility)
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var debounceItem: DispatchWorkItem?
    private var reopenItem: DispatchWorkItem?
    private var reopenAttempts = 0
    private var missingAnnounced = false
    private var stopped = false

    public init(url: URL, debounce: Duration = .milliseconds(200), handler: @escaping Handler) {
        self.path = url.path(percentEncoded: false)
        self.debounceMS = max(0, Int(debounce / .milliseconds(1)))
        self.handler = handler
        lock.lock()
        if !armLocked() {
            scheduleReopenLocked(after: 50)
        }
        lock.unlock()
    }

    deinit {
        stop()
    }

    public func stop() {
        lock.lock()
        stopped = true
        source?.cancel()
        source = nil
        debounceItem?.cancel()
        debounceItem = nil
        reopenItem?.cancel()
        reopenItem = nil
        lock.unlock()
    }

    /// Swift Concurrency용. 스트림이 끝나면 감시도 멈춘다.
    public static func events(for url: URL, debounce: Duration = .milliseconds(200)) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let watcher = FileWatcher(url: url, debounce: debounce) { continuation.yield($0) }
            continuation.onTermination = { _ in watcher.stop() }
        }
    }

    // MARK: - 내부. `Locked` 접미 함수는 lock을 잡은 상태에서만 부른다.

    private func armLocked() -> Bool {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.handle(src.data) }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        return true
    }

    private func handle(_ flags: DispatchSource.FileSystemEvent) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
            // vnode가 사라지거나 다른 이름이 됐다. 같은 경로를 다시 열어 본다.
            source?.cancel()
            source = nil
            reopenAttempts = 0
            scheduleReopenLocked(after: 50)
        } else {
            scheduleChangeLocked()
        }
        lock.unlock()
    }

    private func scheduleChangeLocked() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fireChange() }
        debounceItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(debounceMS), execute: item)
    }

    private func fireChange() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        debounceItem = nil
        missingAnnounced = false
        lock.unlock()
        handler(.changed)
    }

    private func scheduleReopenLocked(after milliseconds: Int) {
        reopenItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.tryReopen() }
        reopenItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
    }

    private func tryReopen() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        reopenItem = nil
        if armLocked() {
            // 새 vnode다. 원자적 저장이든 복구든 내용이 바뀐 것으로 본다.
            reopenAttempts = 0
            scheduleChangeLocked()
            lock.unlock()
            return
        }
        reopenAttempts += 1
        // 50+100+200+400ms 동안 없으면 사라졌다고 알리고, 이후 1초 간격으로 계속 확인한다.
        let announce = !missingAnnounced && reopenAttempts >= 4
        if announce { missingAnnounced = true }
        scheduleReopenLocked(after: reopenAttempts < 5 ? 50 << reopenAttempts : 1000)
        lock.unlock()
        if announce { handler(.disappeared) }
    }
}
