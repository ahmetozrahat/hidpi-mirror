import CoreGraphics
import Foundation

/// A physical, non-built-in display that HiDPI mirroring can be applied to.
struct PhysicalDisplay: Equatable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let sizeInMillimeters: CGSize

    /// Stable across reboots and reconnects, unlike the CGDirectDisplayID.
    var key: String { "\(vendor)-\(model)-\(serial)" }

    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// External panels, skipping built-in screens and our own virtual displays.
    static func onlineExternal() -> [PhysicalDisplay] {
        onlineIDs().compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0, CGDisplayVendorNumber(id) != MirrorController.vendorID else { return nil }
            return PhysicalDisplay(id: id)
        }
    }

    init?(id: CGDirectDisplayID) {
        guard let native = Self.nativeMode(of: id) else { return nil }
        self.id = id
        vendor = CGDisplayVendorNumber(id)
        model = CGDisplayModelNumber(id)
        serial = CGDisplaySerialNumber(id)
        name = Self.localizedName(of: id) ?? "Display \(id)"
        pixelWidth = native.pixelWidth
        pixelHeight = native.pixelHeight
        let current = CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0
        refreshRate = current > 0 ? current : (native.refreshRate > 0 ? native.refreshRate : 60)
        sizeInMillimeters = CGDisplayScreenSize(id)
    }

    /// The display's largest pixel mode, i.e. its native panel resolution.
    private static func nativeMode(of id: CGDirectDisplayID) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        let nativeFlag: UInt32 = 0x0200_0000 // kDisplayModeNativeFlag (IOKit)
        if let native = modes.first(where: { $0.ioFlags & nativeFlag != 0 }) {
            return native
        }
        return modes.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
    }

    private static func localizedName(of id: CGDirectDisplayID) -> String? {
        NSScreenLookup.name(for: id)
    }
}

/// Point sizes offered in the menu, all with the panel's aspect ratio and a 2x backing store.
func scaledResolutions(for display: PhysicalDisplay) -> [(width: Int, height: Int)] {
    let aspect = Double(display.pixelHeight) / Double(display.pixelWidth)
    let widths = [display.pixelWidth, 2304, 2240, 2048, 1920, 1792, 1680, 1600, 1440, 1280]
    var seen = Set<Int>()
    return widths
        .filter { $0 <= display.pixelWidth && seen.insert($0).inserted }
        .map { w in
            // Keep both dimensions even so the 2x backing store maps cleanly.
            let h = Int((Double(w) * aspect / 2).rounded()) * 2
            return (w, h)
        }
}
