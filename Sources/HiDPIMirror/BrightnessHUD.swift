import AppKit

/// An on-screen indicator in the style of macOS Tahoe's volume/brightness HUD: a dark glass card
/// under the menu bar with the device name above a thin slider, shown when the keys are used.
final class BrightnessHUD {
    private var panel: NSPanel?
    private var title: NSTextField?
    private var fill: NSView?
    private var track: NSView?
    private var hideWork: DispatchWorkItem?

    // Measured from the system volume HUD.
    private let size = NSSize(width: 292, height: 62)
    private let cornerRadius: CGFloat = 24
    private let padding: CGFloat = 16
    private let trackHeight: CGFloat = 4
    private let gapBelowMenuBar: CGFloat = 11

    /// `anchor` is the screen frame of the menu bar item the HUD hangs under, like the system one
    /// hangs under the volume icon; without it the HUD goes to the top-right corner.
    func show(level: Double, title text: String, anchor: NSRect?) {
        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = anchor.flatMap(screen(containing:)) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let midX = anchor?.midX ?? (visible.maxX - size.width / 2)
            let x = min(max(midX - size.width / 2, visible.minX + 8), visible.maxX - 8 - size.width)
            panel.setFrameOrigin(NSPoint(x: x, y: visible.maxY - gapBelowMenuBar - size.height))
        }

        title?.stringValue = text
        if let track, let fill {
            fill.frame = NSRect(x: 0, y: 0, width: track.bounds.width * min(1, max(0, level)), height: trackHeight)
        }

        hideWork?.cancel()
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }

        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel?.animator().alphaValue = 0
            } completionHandler: {
                if panel?.alphaValue == 0 { panel?.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
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
        panel.alphaValue = 0

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = makeBackground(content: content)

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: padding, y: size.height - 10 - 17, width: size.width - padding * 2, height: 17)
        content.addSubview(title)

        // Slider row: dim sun, track, bright sun; 16 step dots under the track.
        let rowMidY: CGFloat = size.height - 40
        let low = icon("sun.min.fill", pointSize: 12)
        low.frame = NSRect(x: padding - 1, y: rowMidY - 8, width: 16, height: 16)
        let high = icon("sun.max.fill", pointSize: 15)
        high.frame = NSRect(x: size.width - padding - 18, y: rowMidY - 9, width: 18, height: 18)

        let trackX: CGFloat = 31
        let trackWidth = high.frame.minX - 7 - trackX
        let track = NSView(frame: NSRect(x: trackX, y: rowMidY - trackHeight / 2, width: trackWidth, height: trackHeight))
        track.wantsLayer = true
        track.layer?.cornerRadius = trackHeight / 2
        track.layer?.masksToBounds = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor

        let fill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: trackHeight))
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.white.cgColor
        track.addSubview(fill)

        let dotSize: CGFloat = 2
        let steps = BrightnessSlider.steps
        for i in 0..<steps {
            let x = trackX + 6 + (trackWidth - 12) * CGFloat(i) / CGFloat(steps - 1)
            let dot = NSView(frame: NSRect(x: x - dotSize / 2, y: rowMidY - 7 - dotSize, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
            content.addSubview(dot)
        }

        [low, track, high].forEach(content.addSubview)
        self.title = title
        self.track = track
        self.fill = fill
        return panel
    }

    /// Liquid Glass on macOS 26 and later, the HUD material before that.
    private func makeBackground(content: NSView) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = cornerRadius
            // Private variant 6: a darker glass with a light rim, close to the system HUD and
            // readable with white content over bright windows. The public styles render flat here.
            glass.setValue(6, forKey: "_variant")
            glass.contentView = content
            return glass
        }
        let background = NSVisualEffectView(frame: content.frame)
        background.appearance = NSAppearance(named: .darkAqua)
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.masksToBounds = true
        background.addSubview(content)
        return background
    }

    private func icon(_ name: String, pointSize: CGFloat) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        view.contentTintColor = .white
        view.imageScaling = .scaleNone
        return view
    }
}
