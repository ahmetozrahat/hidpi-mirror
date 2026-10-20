import AppKit

/// The menu's brightness row: a native slider between a dim and a bright sun, aligned with the
/// menu's text and separators. It snaps to the same 16 steps as the brightness keys, without
/// drawing tick marks.
final class BrightnessSlider: NSView {
    static let steps = 16

    var level: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = Self.snap(newValue) }
    }
    var onChange: ((Double) -> Void)?

    private let slider: NSSlider
    private var lastSent: Double

    // Matches where NSMenu draws item titles (after the checkmark column) and where separators end.
    private let leadingInset: CGFloat = 30
    private let trailingInset: CGFloat = 16
    private let iconSize: CGFloat = 16
    private let gap: CGFloat = 8

    init(level: Double) {
        lastSent = Self.snap(level)
        slider = NSSlider(value: lastSent, minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        // NSMenu resizes item views to the menu width when they are width-sizable.
        autoresizingMask = [.width]

        let iconY = (bounds.height - iconSize) / 2
        let low = icon("sun.min.fill")
        low.frame = NSRect(x: leadingInset, y: iconY, width: iconSize, height: iconSize)
        low.autoresizingMask = [.maxXMargin]

        let high = icon("sun.max.fill")
        high.frame = NSRect(x: bounds.maxX - trailingInset - iconSize, y: iconY, width: iconSize, height: iconSize)
        high.autoresizingMask = [.minXMargin]

        let sliderX = low.frame.maxX + gap
        slider.frame = NSRect(x: sliderX, y: (bounds.height - 20) / 2, width: high.frame.minX - gap - sliderX, height: 20)
        slider.autoresizingMask = [.width]
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.setAccessibilityLabel("Parlaklık")

        [low, slider, high].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func icon(_ name: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        view.contentTintColor = .secondaryLabelColor
        return view
    }

    // MARK: - Snapping

    @objc private func sliderChanged() {
        let snapped = Self.snap(slider.doubleValue)
        slider.doubleValue = snapped
        guard snapped != lastSent else { return }
        lastSent = snapped
        onChange?(snapped)
    }

    private static func snap(_ value: Double) -> Double {
        (min(1, max(0, value)) * Double(steps)).rounded() / Double(steps)
    }
}
