import AppKit

/// A Control Center–style brightness bar for the menu: a thick capsule that fills from the left,
/// a sun inside the track and the percentage on the right. Click, drag or scroll to change it.
final class BrightnessSlider: NSView {
    var level: Double = 0 {
        didSet { needsLayout = true; updateLabel() }
    }
    var onChange: ((Double) -> Void)?

    private let track = CALayer()
    private let fill = CALayer()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    private let trackHeight: CGFloat = 22
    private let labelWidth: CGFloat = 40
    // Lines the bar up with the menu's text and separators.
    private let leadingInset: CGFloat = 14
    private let trailingInset: CGFloat = 14

    init(level: Double) {
        self.level = level
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 34))
        // NSMenu resizes item views to the menu width when they are width-sizable.
        autoresizingMask = [.width]
        wantsLayer = true

        track.cornerRadius = trackHeight / 2
        track.masksToBounds = true
        track.addSublayer(fill)
        layer?.addSublayer(track)

        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        addSubview(icon)

        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        addSubview(label)

        setAccessibilityRole(.slider)
        setAccessibilityLabel("Parlaklık")
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let trackRect = trackFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = trackRect
        // Never narrower than the capsule's height, so the left end stays round at 0 %.
        let fillWidth = max(trackHeight, trackRect.width * level)
        fill.frame = NSRect(x: 0, y: 0, width: fillWidth, height: trackHeight)
        fill.cornerRadius = trackHeight / 2
        CATransaction.commit()

        icon.frame = NSRect(x: trackRect.minX + 5, y: trackRect.minY + 3, width: 16, height: 16)
        label.frame = NSRect(x: bounds.maxX - trailingInset - labelWidth, y: (bounds.height - 17) / 2, width: labelWidth, height: 17)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    // MARK: - Input

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { setLevel(from: event) }
    override func mouseDragged(with event: NSEvent) { setLevel(from: event) }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 300 : event.scrollingDeltaY / 30
        let horizontal = event.hasPreciseScrollingDeltas ? -event.scrollingDeltaX / 300 : 0
        commit(level + Double(delta + horizontal) * (event.isDirectionInvertedFromDevice ? -1 : 1))
    }

    override func accessibilityValue() -> Any? { level }

    // MARK: - Private

    private var trackFrame: NSRect {
        let width = bounds.width - leadingInset - trailingInset - labelWidth - 8
        return NSRect(x: leadingInset, y: (bounds.height - trackHeight) / 2, width: max(0, width), height: trackHeight)
    }

    private func setLevel(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = trackFrame
        commit(Double((point.x - rect.minX) / rect.width))
    }

    private func commit(_ newLevel: Double) {
        let clamped = min(1, max(0, newLevel))
        guard clamped != level else { return }
        level = clamped
        onChange?(clamped)
    }

    private func updateLabel() {
        label.stringValue = "\(Int((level * 100).rounded()))%"
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            fill.backgroundColor = NSColor.labelColor.withAlphaComponent(0.85).cgColor
        }
        // The sun sits on the fill, so it takes the inverse colour to stay readable.
        icon.contentTintColor = .windowBackgroundColor
    }
}
