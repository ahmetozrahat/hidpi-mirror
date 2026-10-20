import PrivateAPIs
import AppKit
import CoreGraphics
import Foundation

enum MirrorError: LocalizedError {
    case virtualDisplayFailed
    case leftoverVirtualDisplay
    case virtualDisplayNeverAppeared
    case noHiDPIMode(width: Int, height: Int)
    case configuration(CGError)

    var errorDescription: String? {
        switch self {
        case .virtualDisplayFailed: "Sanal ekran oluşturulamadı."
        case .leftoverVirtualDisplay: "Önceki oturumdan kalan bir sanal ekran var. Oturumu kapatıp açınca temizlenir."
        case .virtualDisplayNeverAppeared: "Sanal ekran sistemde görünmedi."
        case let .noHiDPIMode(w, h): "\(w)×\(h) için HiDPI modu bulunamadı."
        case let .configuration(err): "Ekran yapılandırması başarısız (CGError \(err.rawValue))."
        }
    }
}

/// Renders the desktop on a HiDPI virtual display and mirrors the physical display to it,
/// so a non-Retina panel gets a 2x backing store downsampled to its native resolution.
final class MirrorController {
    static let vendorID: UInt32 = 0x4844 // "HD"

    private(set) var virtualDisplay: CGVirtualDisplay?
    private(set) var physical: PhysicalDisplay?
    private(set) var resolution: (width: Int, height: Int)?

    var isActive: Bool { virtualDisplay != nil }
    var virtualDisplayID: CGDirectDisplayID? { virtualDisplay?.displayID }

    func start(on display: PhysicalDisplay, width: Int, height: Int) throws {
        stop()

        let virtual = try makeVirtualDisplay(for: display, resolutions: scaledResolutions(for: display))
        virtualDisplay = virtual
        physical = display

        do {
            try waitUntilOnline(virtual.displayID)
            try apply(width: width, height: height)
        } catch {
            stop()
            throw error
        }
    }

    /// Creates the virtual display only, leaving the physical display alone. Used by `--probe`.
    func probe(on display: PhysicalDisplay) throws -> CGDirectDisplayID {
        stop()
        let virtual = try makeVirtualDisplay(for: display, resolutions: scaledResolutions(for: display))
        virtualDisplay = virtual
        try waitUntilOnline(virtual.displayID)
        return virtual.displayID
    }

    /// Switches the virtual display to another point size; mirroring stays in place.
    func apply(width: Int, height: Int) throws {
        guard let virtual = virtualDisplay, let physical else { return }
        guard let mode = hiDPIMode(of: virtual.displayID, width: width, height: height) else {
            throw MirrorError.noHiDPIMode(width: width, height: height)
        }

        // The panel must run at its native resolution while mirroring, or the 2x image is
        // downsampled to a scaled mode and comes out blurry. This has to be its own
        // configuration: changing a display's mode while mirroring it is rejected (1010).
        if CGDisplayMirrorsDisplay(physical.id) == kCGNullDirectDisplay,
           let current = CGDisplayCopyDisplayMode(physical.id), current.pixelWidth != physical.pixelWidth,
           let native = lowResolutionMode(of: physical, width: physical.pixelWidth, height: physical.pixelHeight) {
            try configure { CGConfigureDisplayWithDisplayMode($0, physical.id, native, nil) }
        }

        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config))
        CGConfigureDisplayWithDisplayMode(config, virtual.displayID, mode, nil)
        CGConfigureDisplayMirrorOfDisplay(config, physical.id, virtual.displayID)
        // .forSession: nothing is persisted, so a crash or quit leaves the panel untouched.
        let result = CGCompleteDisplayConfiguration(config, .forSession)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw MirrorError.configuration(result)
        }
        resolution = (width, height)
    }

    /// Ends mirroring. The panel keeps the same "looks like" size in a regular (non-HiDPI) mode
    /// when it has one, so turning HiDPI off doesn't suddenly shrink or enlarge everything.
    func stop() {
        if let physical, CGDisplayIsOnline(physical.id) != 0 {
            try? configure { CGConfigureDisplayMirrorOfDisplay($0, physical.id, kCGNullDirectDisplay) }
            // Separate step, for the same reason as in apply().
            if let resolution,
               let mode = lowResolutionMode(of: physical, width: resolution.width, height: resolution.height) {
                try? configure { CGConfigureDisplayWithDisplayMode($0, physical.id, mode, nil) }
            }
        }
        // Releasing the object removes the virtual display from the system.
        virtualDisplay = nil
        physical = nil
        resolution = nil
    }

    /// Tears down and gives WindowServer a moment to process the removal before the process exits.
    /// Exiting while the virtual display is still being set up can leave it behind until logout.
    func stopAndDrain() {
        stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    // MARK: - Private

    private func makeVirtualDisplay(
        for display: PhysicalDisplay,
        resolutions: [(width: Int, height: Int)]
    ) throws -> CGVirtualDisplay {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "HiDPI \(display.name)"
        descriptor.maxPixelsWide = UInt32(display.pixelWidth * 2)
        descriptor.maxPixelsHigh = UInt32(display.pixelHeight * 2)
        descriptor.sizeInMillimeters = display.sizeInMillimeters.width > 0
            ? display.sizeInMillimeters
            : CGSize(width: 600, height: 340)
        // Own IDs so macOS does not merge its saved arrangement with the real panel.
        descriptor.vendorID = Self.vendorID
        descriptor.productID = display.model & 0xFFFF
        descriptor.serialNum = display.serial
        // sRGB primaries and D65 white point.
        descriptor.redPrimary = CGPoint(x: 0.640, y: 0.330)
        descriptor.greenPrimary = CGPoint(x: 0.300, y: 0.600)
        descriptor.bluePrimary = CGPoint(x: 0.150, y: 0.060)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)

        let virtual = CGVirtualDisplay(descriptor: descriptor)
        guard virtual.displayID != 0 else {
            // macOS refuses a second display with the same identity, which happens when a
            // previous instance's virtual display outlived its process.
            let leftover = PhysicalDisplay.onlineIDs().contains { CGDisplayVendorNumber($0) == Self.vendorID }
            throw leftover ? MirrorError.leftoverVirtualDisplay : MirrorError.virtualDisplayFailed
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // With hiDPI set, each mode is a point size and macOS adds the 2x pixel variant.
        settings.modes = resolutions.map {
            CGVirtualDisplayMode(width: UInt32($0.width), height: UInt32($0.height), refreshRate: display.refreshRate)
        }
        guard virtual.apply(settings) else { throw MirrorError.virtualDisplayFailed }
        return virtual
    }

    private func waitUntilOnline(_ id: CGDirectDisplayID) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if CGDisplayIsOnline(id) != 0, hasAnyMode(id) { return }
            if let event = NSApp?.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
        }
        throw MirrorError.virtualDisplayNeverAppeared
    }

    private func hasAnyMode(_ id: CGDirectDisplayID) -> Bool {
        !(allModes(of: id).isEmpty)
    }

    func allModes(of id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    /// A 1x mode of the given size on the physical panel, at its current refresh rate if possible.
    private func lowResolutionMode(of display: PhysicalDisplay, width: Int, height: Int) -> CGDisplayMode? {
        let candidates = allModes(of: display.id).filter {
            $0.width == width && $0.height == height && $0.pixelWidth == width && $0.isUsableForDesktopGUI()
        }
        return candidates.first { $0.refreshRate == display.refreshRate }
            ?? candidates.max { $0.refreshRate < $1.refreshRate }
    }

    private func hiDPIMode(of id: CGDirectDisplayID, width: Int, height: Int) -> CGDisplayMode? {
        allModes(of: id)
            .filter { $0.width == width && $0.height == height && $0.pixelWidth == width * 2 }
            .max { $0.refreshRate < $1.refreshRate }
    }

    /// Runs one display configuration transaction for the session.
    private func configure(_ body: (CGDisplayConfigRef?) -> Void) throws {
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config))
        body(config)
        let result = CGCompleteDisplayConfiguration(config, .forSession)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw MirrorError.configuration(result)
        }
    }

    private func check(_ error: CGError) throws {
        guard error == .success else { throw MirrorError.configuration(error) }
    }
}
