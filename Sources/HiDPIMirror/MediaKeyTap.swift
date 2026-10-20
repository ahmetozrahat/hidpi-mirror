import AppKit
import ApplicationServices

/// Intercepts the keyboard's brightness keys (F1/F2) with an event tap.
/// Needs Accessibility permission; until it is granted the tap retries quietly.
final class MediaKeyTap {
    /// Called on key down; return true to swallow the key so macOS doesn't show its "unsupported" HUD.
    typealias Handler = (_ up: Bool, _ fine: Bool) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var swallowing = false

    private static let systemDefined = CGEventType(rawValue: 14)! // NX_SYSDEFINED
    private static let brightnessUp = 2 // NX_KEYTYPE_BRIGHTNESS_UP
    private static let brightnessDown = 3 // NX_KEYTYPE_BRIGHTNESS_DOWN

    var isRunning: Bool { tap != nil }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start(prompt: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), install() { return }

        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.install() else { return }
            timer.invalidate()
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
    }

    private func install() -> Bool {
        let mask = CGEventMask(1) << Self.systemDefined.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let this = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return this.handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == Self.systemDefined, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
        guard keyCode == Self.brightnessUp || keyCode == Self.brightnessDown else {
            return Unmanaged.passUnretained(event)
        }
        let isDown = (nsEvent.data1 & 0xFF00) >> 8 == 0xA
        // ⌥⇧ for quarter steps, matching macOS on built-in displays.
        let fine = nsEvent.modifierFlags.contains([.option, .shift])

        // Swallow the release too when the press was handled, otherwise macOS still reacts to it.
        if isDown {
            swallowing = handler(keyCode == Self.brightnessUp, fine)
        }
        return swallowing ? nil : Unmanaged.passUnretained(event)
    }
}
