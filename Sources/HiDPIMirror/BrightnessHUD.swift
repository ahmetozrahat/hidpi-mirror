import AppKit

/// A small on-screen indicator like the system brightness HUD, shown when the keys are used.
final class BrightnessHUD {
    private var panel: NSPanel?
    private var fill: NSView?
    private var track: NSView?
    private var hideWork: DispatchWorkItem?

    private let size = NSSize(width: 200, height: 200)
    private let barInset: CGFloat = 24
    private let barHeight: CGFloat = 8

    func show(level: Double) {
        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = NSScreen.main {
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 140))
        }

        if let track, let fill {
            fill.frame = NSRect(x: 0, y: 0, width: track.bounds.width * level, height: barHeight)
        }

        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel?.animator().alphaValue = 0
            } completionHandler: {
                panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        panel.contentView = background

        let icon = NSImageView(frame: NSRect(x: (size.width - 80) / 2, y: 70, width: 80, height: 80))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Parlaklık")?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .regular))
        icon.contentTintColor = .labelColor
        background.addSubview(icon)

        let track = NSView(frame: NSRect(x: barInset, y: 34, width: size.width - barInset * 2, height: barHeight))
        track.wantsLayer = true
        track.layer?.cornerRadius = barHeight / 2
        track.layer?.masksToBounds = true
        background.addSubview(track)

        let fill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: barHeight))
        fill.wantsLayer = true
        track.addSubview(fill)

        // Layer colours don't follow appearance changes, so resolve them in the panel's appearance.
        background.effectiveAppearance.performAsCurrentDrawingAppearance {
            track.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor
            fill.layer?.backgroundColor = NSColor.labelColor.cgColor
        }

        self.track = track
        self.fill = fill
        return panel
    }
}
