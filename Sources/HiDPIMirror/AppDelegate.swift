import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = MirrorController()
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var lastError: String?
    private var signalSources: [DispatchSourceSignal] = []
    private var brightness: BrightnessController?
    private var mediaKeys: MediaKeyTap!
    private let hud = BrightnessHUD()
    private weak var brightnessSlider: BrightnessSlider?

    private enum Key {
        static let enabled = "enabled"
        static let displayKey = "displayKey"
        static let width = "width"
        static let height = "height"
        static let brightness = "brightness"
        static let brightnessKeys = "brightnessKeys"
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // ⌃⌥⌘H toggles, so there is always a way back even if the screen looks wrong.
        hotKey = HotKey(keyCode: 4, modifiers: [.control, .option, .command]) { [weak self] in
            self?.toggle()
        }

        installSignalHandlers()

        defaults.register(defaults: [Key.brightnessKeys: true])
        mediaKeys = MediaKeyTap { [weak self] up, fine in
            guard let self, let brightness = self.brightness else { return false }
            brightness.step(up: up, fine: fine)
            self.hud.show(level: brightness.level)
            return true
        }
        if defaults.bool(forKey: Key.brightnessKeys) { mediaKeys.start(prompt: true) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )

        if defaults.bool(forKey: Key.enabled) { enable() }
        refreshBrightness()
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stopAndDrain()
    }

    /// Quit cleanly on SIGTERM/SIGINT too, so the virtual display is never left behind.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Actions

    private func toggle() {
        if controller.isActive {
            disable()
        } else {
            enable()
        }
    }

    private func enable(display explicit: PhysicalDisplay? = nil, width: Int? = nil, height: Int? = nil) {
        guard let display = explicit ?? preferredDisplay() else {
            lastError = "Harici ekran bulunamadı."
            updateIcon()
            return
        }
        let resolutions = scaledResolutions(for: display)
        let saved = (defaults.integer(forKey: Key.width), defaults.integer(forKey: Key.height))
        let target = (width ?? saved.0, height ?? saved.1)
        let size = resolutions.first { $0.width == target.0 && $0.height == target.1 } ?? resolutions[0]

        do {
            try controller.start(on: display, width: size.width, height: size.height)
            lastError = nil
            defaults.set(true, forKey: Key.enabled)
            defaults.set(display.key, forKey: Key.displayKey)
            defaults.set(size.width, forKey: Key.width)
            defaults.set(size.height, forKey: Key.height)
        } catch {
            lastError = error.localizedDescription
        }
        refreshBrightness()
        updateIcon()
    }

    private func disable() {
        controller.stop()
        defaults.set(false, forKey: Key.enabled)
        updateIcon()
    }

    private func preferredDisplay() -> PhysicalDisplay? {
        let displays = PhysicalDisplay.onlineExternal()
        let savedKey = defaults.string(forKey: Key.displayKey)
        return displays.first { $0.key == savedKey } ?? displays.first
    }

    @objc private func screensChanged() {
        // The panel was unplugged: drop the virtual display so windows don't strand on it.
        if let physical = controller.physical,
           !PhysicalDisplay.onlineExternal().contains(where: { $0.key == physical.key }) {
            controller.stop()
            updateIcon()
        }
        refreshBrightness()
    }

    /// Points brightness control at the panel in use, recreating it after reconnects or a display switch.
    private func refreshBrightness() {
        guard let display = controller.physical ?? preferredDisplay() else {
            brightness = nil
            return
        }
        guard brightness?.displayKey != display.key else { return }
        let saved = defaults.object(forKey: Key.brightness) as? Double
        brightness = BrightnessController(display: display, savedLevel: saved)
        brightness?.onChange = { [weak self] level in
            self?.defaults.set(level, forKey: Key.brightness)
            self?.brightnessSlider?.level = level
        }
    }

    @objc private func screensDidWake() {
        // The panel comes back at its own brightness; push ours again once it accepts DDC.
        // A few tries, since panels take a variable while to wake up after the signal returns.
        for delay in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.brightness?.reapply()
            }
        }
    }

    @objc private func didWake() {
        // Reconnect after sleep if mirroring was on but the panel came back without it.
        guard defaults.bool(forKey: Key.enabled) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let mirrored = self.controller.physical.map { CGDisplayMirrorsDisplay($0.id) != kCGNullDirectDisplay } ?? false
            if !mirrored { self.enable() }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let lastError {
            let item = NSMenuItem(title: "⚠︎ \(lastError)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let toggleItem = NSMenuItem(
            title: controller.isActive ? "HiDPI'ı kapat" : "HiDPI'ı aç",
            action: #selector(toggleFromMenu), keyEquivalent: "h"
        )
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)

        if let brightness {
            menu.addItem(.separator())
            menu.addItem(header("Parlaklık"))
            let slider = BrightnessSlider(level: brightness.level)
            slider.onChange = { [weak self] level in self?.brightness?.set(level) }
            brightnessSlider = slider
            let item = NSMenuItem()
            item.view = slider
            menu.addItem(item)
        }

        let displays = PhysicalDisplay.onlineExternal()
        guard let current = controller.physical ?? preferredDisplay() else {
            addFooter(to: menu)
            return
        }

        if displays.count > 1 {
            menu.addItem(.separator())
            menu.addItem(header("Ekran"))
            for display in displays {
                let item = NSMenuItem(title: display.name, action: #selector(selectDisplay(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = display.key
                item.state = display.key == current.key ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(header("Görünüm (\(current.name), \(Int(current.refreshRate)) Hz)"))
        let active = controller.resolution
        for size in scaledResolutions(for: current) {
            let native = size.width == current.pixelWidth ? "  (yerel)" : ""
            let item = NSMenuItem(
                title: "\(size.width) × \(size.height)\(native)",
                action: #selector(selectResolution(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = [size.width, size.height]
            item.state = (active?.width == size.width && active?.height == size.height) ? .on : .off
            menu.addItem(item)
        }

        addFooter(to: menu)
    }

    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Girişte başlat", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let keys = NSMenuItem(title: "Parlaklık tuşlarını kullan", action: #selector(toggleBrightnessKeys), keyEquivalent: "")
        keys.target = self
        keys.state = defaults.bool(forKey: Key.brightnessKeys) ? .on : .off
        menu.addItem(keys)
        menu.addItem(NSMenuItem(title: "Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleBrightnessKeys() {
        let enabled = !defaults.bool(forKey: Key.brightnessKeys)
        defaults.set(enabled, forKey: Key.brightnessKeys)
        if enabled {
            mediaKeys.start(prompt: true)
        } else {
            mediaKeys.stop()
        }
    }

    @objc private func toggleFromMenu() { toggle() }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let display = PhysicalDisplay.onlineExternal().first(where: { $0.key == key }) else { return }
        defaults.set(key, forKey: Key.displayKey)
        if controller.isActive { enable(display: display) }
    }

    @objc private func selectResolution(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? [Int] else { return }
        if controller.isActive {
            do {
                try controller.apply(width: size[0], height: size[1])
                lastError = nil
                defaults.set(size[0], forKey: Key.width)
                defaults.set(size[1], forKey: Key.height)
            } catch {
                lastError = error.localizedDescription
            }
            updateIcon()
        } else {
            enable(width: size[0], height: size[1])
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            lastError = "Girişte başlatma ayarlanamadı: \(error.localizedDescription)"
            updateIcon()
        }
    }

    private func updateIcon() {
        let symbol = lastError != nil ? "exclamationmark.triangle" : "display"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HiDPI Mirror")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !controller.isActive && lastError == nil
    }
}
