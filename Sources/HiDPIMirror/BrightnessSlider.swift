import AppKit

/// The menu's brightness control: a native NSSlider that snaps to the same 16 steps as the
/// brightness keys, between a dim and a bright sun, spanning the menu's width.
final class BrightnessSlider: NSView {
    static let steps = 16

    var level: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue }
    }
    var onChange: ((Double) -> Void)?

    private let slider: NSSlider
    private let inset: CGFloat = 14
    private let iconSize: CGFloat = 16
    private let gap: CGFloat = 6

    init(level: Double) {
        slider = NSSlider(value: level, minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 34))
        // NSMenu resizes item views to the menu width when they are width-sizable.
        autoresizingMask = [.width]

        let low = icon("sun.min")
        low.frame = NSRect(x: inset, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        low.autoresizingMask = [.maxXMargin]

        let high = icon("sun.max")
        high.frame = NSRect(x: bounds.maxX - inset - iconSize, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        high.autoresizingMask = [.minXMargin]

        let sliderX = low.frame.maxX + gap
        slider.frame = NSRect(x: sliderX, y: 4, width: high.frame.minX - gap - sliderX, height: bounds.height - 8)
        slider.autoresizingMask = [.width]
        slider.numberOfTickMarks = Self.steps + 1
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)

        [low, slider, high].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func sliderChanged() {
        onChange?(slider.doubleValue)
    }

    private func icon(_ name: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.contentTintColor = .secondaryLabelColor
        return view
    }
}
