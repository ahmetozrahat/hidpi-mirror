import Foundation

/// Brightness of one external panel via DDC. Writes are coalesced on a serial queue so dragging
/// a slider or holding a key never queues up a backlog of slow I2C transactions.
final class BrightnessController {
    let displayKey: String
    private let ddc: DDCDisplay
    private let queue = DispatchQueue(label: "hidpi-mirror.ddc")
    private var pending: UInt16?
    private var writing = false

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

        queue.async { [weak self] in
            guard let self else { return }
            self.pending = value
            guard !self.writing else { return }
            self.writing = true
            while let next = self.pending {
                self.pending = nil
                self.ddc.write(.brightness, value: next)
            }
            self.writing = false
        }
    }

    /// Steps like the built-in display: 16 steps, or 64 with fine stepping.
    func step(up: Bool, fine: Bool) {
        let size = fine ? 1.0 / 64 : 1.0 / 16
        let steps = (level / size).rounded()
        set((steps + (up ? 1 : -1)) * size)
    }
}
