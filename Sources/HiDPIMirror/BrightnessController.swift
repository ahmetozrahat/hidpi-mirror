import Foundation

/// Brightness of one external panel via DDC. Writes are coalesced on a serial queue so dragging
/// a slider or holding a key never queues up a backlog of slow I2C transactions: only the latest
/// value is sent, and once input settles it is sent again in case the monitor dropped it.
final class BrightnessController {
    let displayKey: String
    private let ddc: DDCDisplay
    private let queue = DispatchQueue(label: "hidpi-mirror.ddc")
    // `pending`, `draining` and `confirm` are shared with the main thread; `lastWritten` is queue-only.
    private let lock = NSLock()
    private var pending: UInt16?
    private var draining = false
    private var confirm: DispatchWorkItem?
    private var lastWritten: UInt16?

    /// Gap between writes; most monitors ignore DDC commands that arrive closer together.
    private let writeInterval: useconds_t = 25_000
    private let confirmDelay: TimeInterval = 0.3

    /// 0…1. Starts from the last saved value and is replaced by the monitor's reading when it arrives.
    private(set) var level: Double
    private(set) var maxValue: UInt16 = 100
    var onChange: ((Double) -> Void)?

    init?(display: PhysicalDisplay, savedLevel: Double?) {
        guard let ddc = DDCDisplay.find(for: display) else { return nil }
        self.ddc = ddc
        displayKey = display.key
        level = savedLevel ?? 0.5

        queue.async { [weak self] in
            guard let self, let reading = self.ddc.read(.brightness) else { return }
            DispatchQueue.main.async {
                self.maxValue = reading.max
                self.level = min(1, Double(reading.current) / Double(reading.max))
                self.onChange?(self.level)
            }
        }
    }

    func set(_ newLevel: Double) {
        level = min(1, max(0, newLevel))
        let value = UInt16((level * Double(maxValue)).rounded())
        onChange?(level)

        lock.lock()
        pending = value
        confirm?.cancel()
        let startDrain = !draining
        draining = true
        lock.unlock()

        if startDrain {
            queue.async { [weak self] in self?.drain() }
        }
    }

    /// Runs on `queue`. Values set while a write is in flight replace each other, so the
    /// monitor only ever sees the newest one.
    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else {
                draining = false
                lock.unlock()
                break
            }
            pending = nil
            lock.unlock()

            if next != lastWritten {
                ddc.write(.brightness, value: next)
                lastWritten = next
                usleep(writeInterval)
            }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let value = self.lastWritten else { return }
            self.ddc.write(.brightness, value: value)
        }
        lock.lock()
        confirm = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + confirmDelay, execute: work)
    }

    /// Steps like the built-in display: 16 steps, or 64 with fine stepping.
    func step(up: Bool, fine: Bool) {
        let size = fine ? 1.0 / 64 : 1.0 / 16
        let steps = (level / size).rounded()
        set((steps + (up ? 1 : -1)) * size)
    }
}
