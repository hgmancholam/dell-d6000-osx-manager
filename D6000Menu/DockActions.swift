import AppKit
import CoreGraphics
import IOKit

enum DockActions {
    private static let xpcServiceLabel = "com.displaylink.XpcService"
    private static let exclusiveAccessError = Int32(bitPattern: 0xE00002C5)

    static func restartDisplayLink() async -> String {
        await closeAgent()
        let serviceRestarted = await Task.detached { restartXPCService() }.value
        if let openError = await openAgent() {
            return openError
        }
        return serviceRestarted
            ? "DisplayLink Manager y su servicio se reiniciaron."
            : "DisplayLink Manager se abrió, pero su servicio no se pudo reiniciar."
    }

    static func reconfigureDisplays() -> String {
        let reapplied = reapplyExternalDisplayModes()
        return reapplied == 0
            ? "No se pudo reaplicar el modo: macOS no aceptó el cambio o no ve monitores externos."
            : "Modo reaplicado en \(reapplied) monitores externos."
    }

    static func resetUSB(devices: [USBDevice]) async -> String {
        guard !devices.isEmpty else { return "No hay dispositivos del dock que reiniciar." }

        // DisplayLinkUserAgent holds the dock device exclusively, so it must exit before re-enumeration.
        await closeAgent()

        var accepted: [String] = []
        var failures: [String] = []
        for device in devices {
            let result = await reenumerateWhenReleased(device)
            if result == 0 {
                accepted.append(device.name)
            } else {
                failures.append("\(device.name): \(String(cString: mach_error_string(result)))")
            }
        }

        try? await Task.sleep(for: .seconds(2))
        let openError = await openAgent()

        var parts: [String] = []
        if !accepted.isEmpty { parts.append("Reinicio USB aceptado: \(accepted.joined(separator: ", ")).") }
        if !failures.isEmpty { parts.append("Reinicio USB rechazado: \(failures.joined(separator: "; ")).") }
        parts.append(openError ?? "DisplayLink Manager se volvió a abrir.")
        return parts.joined(separator: " ")
    }

    private static func reenumerateWhenReleased(_ device: USBDevice) async -> Int32 {
        var result = d6000_usb_reenumerate(device.id)
        for _ in 0..<10 where result == exclusiveAccessError {
            try? await Task.sleep(for: .milliseconds(500))
            result = d6000_usb_reenumerate(device.id)
        }
        return result
    }

    private static func closeAgent() async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: HardwareScanner.agentBundleID)
        running.forEach { $0.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    private static func openAgent() async -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: HardwareScanner.agentBundleID) else {
            return "DisplayLink Manager no está instalado."
        }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return nil
        } catch {
            return "No se pudo abrir DisplayLink Manager: \(error.localizedDescription)"
        }
    }

    private static func restartXPCService() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(xpcServiceLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func reapplyExternalDisplayModes() -> Int {
        let externals = HardwareScanner.displays().filter { !$0.isBuiltin }
        guard !externals.isEmpty else { return 0 }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return 0 }

        var applied = 0
        for display in externals {
            if let mode = CGDisplayCopyDisplayMode(display.id),
               CGConfigureDisplayWithDisplayMode(config, display.id, mode, nil) == .success {
                applied += 1
            }
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            return 0
        }
        return applied
    }
}
