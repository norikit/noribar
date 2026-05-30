import Foundation

/// Tiny thread-safe accumulator for the spike's measurements.
final class Metrics {
    static let shared = Metrics()

    private let lock = NSLock()
    private var tickSeconds: [Double] = []
    private(set) var reloadCount = 0

    /// Per-tick = one `bar.every` cycle: Lua callback + command emission
    /// (measured on the Lua queue, before the main-thread hop).
    func recordTick(seconds: Double) {
        lock.lock(); tickSeconds.append(seconds); lock.unlock()
    }

    func noteReload() {
        lock.lock(); reloadCount += 1; lock.unlock()
    }

    /// Current resident memory footprint (MB) of this process.
    static func residentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }

    func snapshot() -> String {
        lock.lock(); let ticks = tickSeconds; let reloads = reloadCount; lock.unlock()
        guard !ticks.isEmpty else {
            return "metrics: no ticks yet; reloads=\(reloads); rss=\(String(format: "%.1f", Metrics.residentMemoryMB()))MB"
        }
        let sorted = ticks.sorted()
        let mean = ticks.reduce(0, +) / Double(ticks.count)
        let p50 = sorted[sorted.count / 2]
        let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        let us = { (s: Double) in String(format: "%.1fµs", s * 1_000_000) }
        return """
        metrics: ticks=\(ticks.count) mean=\(us(mean)) p50=\(us(p50)) p99=\(us(p99)) max=\(us(sorted.last!)) \
        reloads=\(reloads) rss=\(String(format: "%.1f", Metrics.residentMemoryMB()))MB
        """
    }
}
