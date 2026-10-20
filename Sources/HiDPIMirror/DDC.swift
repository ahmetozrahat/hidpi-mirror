import Foundation
import IOKit
import PrivateAPIs

/// DDC/CI over the I2C bus Apple Silicon exposes per external display (DCPAVServiceProxy).
/// Calls block for tens of milliseconds, so keep them off the main thread.
final class DDCDisplay {
    enum VCP: UInt8 {
        case brightness = 0x10
    }

    private let service: IOAVService

    private init(service: IOAVService) {
        self.service = service
    }

    /// Finds the I2C service for a physical display by walking the registry: each external
    /// DCPAVServiceProxy follows the framebuffer it belongs to, whose attributes carry the EDID IDs.
    static func find(for display: PhysicalDisplay) -> DDCDisplay? {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var lastAttributes: [String: Any]?
        var candidates: [(attributes: [String: Any]?, service: IOAVService)] = []

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            switch className(of: entry) {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                let attributes = property(entry, "DisplayAttributes") as? [String: Any]
                lastAttributes = attributes?["ProductAttributes"] as? [String: Any]
            case "DCPAVServiceProxy":
                guard property(entry, "Location") as? String == "External",
                      let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
                candidates.append((lastAttributes, service))
            default:
                continue
            }
        }

        let match = candidates.first { candidate in
            guard let attributes = candidate.attributes else { return false }
            return (attributes["LegacyManufacturerID"] as? UInt32) == display.vendor
                && (attributes["ProductID"] as? UInt32) == display.model
                && (attributes["SerialNumber"] as? UInt32) == display.serial
        }
        // A single external display needs no matching, which also covers panels with odd EDIDs.
        guard let service = match?.service ?? (candidates.count == 1 ? candidates[0].service : nil) else {
            return nil
        }
        return DDCDisplay(service: service)
    }

    @discardableResult
    func write(_ vcp: VCP, value: UInt16) -> Bool {
        var packet: [UInt8] = [0x84, 0x03, vcp.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)]
        packet.append(checksum(packet))
        // Some monitors drop single writes; sending twice is what MonitorControl and m1ddc do.
        var succeeded = false
        for _ in 0..<2 {
            if IOAVServiceWriteI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == kIOReturnSuccess {
                succeeded = true
            }
            usleep(10_000)
        }
        return succeeded
    }

    func read(_ vcp: VCP) -> (current: UInt16, max: UInt16)? {
        var request: [UInt8] = [0x82, 0x01, vcp.rawValue]
        request.append(checksum(request))

        for _ in 0..<3 {
            guard IOAVServiceWriteI2C(service, 0x37, 0x51, &request, UInt32(request.count)) == kIOReturnSuccess else {
                usleep(20_000)
                continue
            }
            usleep(40_000)
            var reply = [UInt8](repeating: 0, count: 12)
            guard IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess else { continue }

            // Reply: … 0x02 (VCP reply), result 0x00, vcp, type, max hi/lo, current hi/lo.
            for i in 0..<(reply.count - 7) where reply[i] == 0x02 && reply[i + 1] == 0x00 && reply[i + 2] == vcp.rawValue {
                let max = UInt16(reply[i + 4]) << 8 | UInt16(reply[i + 5])
                let current = UInt16(reply[i + 6]) << 8 | UInt16(reply[i + 7])
                if max > 0 { return (current, max) }
            }
        }
        return nil
    }

    // MARK: - Private

    /// XOR of the host address (0x6E), the sub-address (0x51) and the payload.
    private func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0x6E ^ 0x51, ^)
    }

    private static func className(of entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &name)
        return String(cString: name)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
