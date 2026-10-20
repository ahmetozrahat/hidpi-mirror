import AppKit

let app = NSApplication.shared

// `--probe`: create the virtual display without mirroring, list its modes, then remove it.
// Useful after macOS updates to check the private API still behaves.
if CommandLine.arguments.contains("--probe") {
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    guard let display = PhysicalDisplay.onlineExternal().first else {
        print("Harici ekran yok.")
        exit(1)
    }
    print("Fiziksel: \(display.name) \(display.pixelWidth)x\(display.pixelHeight) @ \(display.refreshRate)Hz")
    let controller = MirrorController()
    var status: Int32 = 0
    do {
        let id = try controller.probe(on: display)
        print("Sanal ekran id: \(id)")
        for mode in controller.allModes(of: id) {
            print("  \(mode.width)x\(mode.height) pt  \(mode.pixelWidth)x\(mode.pixelHeight) px  \(mode.refreshRate)Hz")
        }
    } catch {
        print("Hata: \(error.localizedDescription)")
        status = 1
    }
    controller.stopAndDrain()
    exit(status)
}

// `--ddc [value]`: read the external panel's brightness over DDC, optionally setting it first.
if let index = CommandLine.arguments.firstIndex(of: "--ddc") {
    guard let display = PhysicalDisplay.onlineExternal().first, let ddc = DDCDisplay.find(for: display) else {
        print("DDC servisi bulunamadı.")
        exit(1)
    }
    if CommandLine.arguments.count > index + 1, let value = UInt16(CommandLine.arguments[index + 1]) {
        print("Yaz \(value): \(ddc.write(.brightness, value: value) ? "tamam" : "başarısız")")
    }
    if let reading = ddc.read(.brightness) {
        print("Parlaklık: \(reading.current) / \(reading.max)")
    } else {
        print("Okuma başarısız.")
        exit(1)
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
