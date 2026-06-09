import Foundation

/// Watches a single file for external modifications (e.g. edits from Xcode) and
/// invokes a handler so the visual model can refresh. Uses a kqueue-backed
/// `DispatchSource`; no polling.
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.visualuiarchitect.filewatcher")
    private let onChange: @Sendable () -> Void

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    public func start() {
        stop()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.onChange()
            // Editors that replace files (rename/delete) invalidate the fd; rearm.
            if src.data.contains(.rename) || src.data.contains(.delete) {
                self.queue.asyncAfter(deadline: .now() + 0.1) { self.start() }
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
