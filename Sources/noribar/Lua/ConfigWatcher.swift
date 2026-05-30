import Foundation

/// Watches a single file and fires `onChange` (debounced) when it is written or
/// atomically replaced. Handles editors that save-by-rename by re-arming the
/// kqueue descriptor after a rename/delete.
final class ConfigWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "org.norikit.noribar.config-watch")
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() { queue.async { [weak self] in self?.arm() } }

    func stop() {
        queue.async { [weak self] in
            self?.debounce?.cancel()
            self?.source?.cancel()
            self?.source = nil
        }
    }

    private func arm() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File missing (e.g. mid atomic-rename): retry shortly.
            queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arm() }
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = s.data
            self.scheduleChange()
            if flags.contains(.rename) || flags.contains(.delete) {
                // The inode we were watching is gone; rebind to the new file.
                self.source?.cancel()
            }
        }
        s.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
            // If the cancel was due to rename/delete, re-arm onto the replacement.
            if self.source != nil { self.source = nil; self.arm() }
        }
        source = s
        s.resume()
    }

    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}
