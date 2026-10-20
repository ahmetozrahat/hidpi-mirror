import AppKit

/// The menu's brightness control, laid out like a Control Center module on macOS Tahoe:
/// a glass card with a title and a native slider between a dim and a bright sun.
/// The slider snaps to the same 16 steps as the brightness keys, without drawing tick marks.
final class BrightnessSlider: NSView {
    static let steps = 16

    var level: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = Self.snap(newValue) }
    }
    var onChange: ((Double) -> Void)?

    private let slider: NSSlider
    private var lastSent: Double

    private let outerInset: CGFloat = 10
    private let padding: CGFloat = 12
    private let iconSize: CGFloat = 18
    private let gap: CGFloat = 8

    init(level: Double) {
        lastSent = Self.snap(level)
        slider = NSSlider(value: lastSent, minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 76))
        // NSMenu resizes item views to the menu width when they are width-sizable.
        autoresizingMask = [.width]

        let card = makeCard(frame: bounds.insetBy(dx: outerInset, dy: 4))
        card.autoresizingMask = [.width]
        addSubview(card)
        layoutContent(in: contentView(of: card))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    private func layoutContent(in content: NSView) {
        let width = content.bounds.width

        let title = NSTextField(labelWithString: "Parlaklık")
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.textColor = .labelColor
        title.sizeToFit()
        title.frame.origin = NSPoint(x: padding, y: content.bounds.height - padding - title.frame.height + 2)
        title.autoresizingMask = [.maxXMargin, .minYMargin]

        let rowY: CGFloat = padding - 2
        let low = icon("sun.min.fill")
        low.frame = NSRect(x: padding, y: rowY + 1, width: iconSize, height: iconSize)
        low.autoresizingMask = [.maxXMargin]

        let high = icon("sun.max.fill")
        high.frame = NSRect(x: width - padding - iconSize, y: rowY + 1, width: iconSize, height: iconSize)
        high.autoresizingMask = [.minXMargin]

        let sliderX = low.frame.maxX + gap
        slider.frame = NSRect(x: sliderX, y: rowY, width: high.frame.minX - gap - sliderX, height: 20)
        slider.autoresizingMask = [.width]
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.setAccessibilityLabel("Parlaklık")

        [title, low, slider, high].forEach(content.addSubview)
    }

    private func makeCard(frame: NSRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = 18
            let content = NSView(frame: glass.bounds)
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        return effect
    }

    private func contentView(of card: NSView) -> NSView {
        if #available(macOS 26.0, *), let glass = card as? NSGlassEffectView, let content = glass.contentView {
            return content
        }
        return card
    }

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
