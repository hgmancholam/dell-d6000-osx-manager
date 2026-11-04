import CoreGraphics
import Foundation

struct USBDevice: Identifiable, Hashable {
    let id: UInt64
    let vendorID: Int
    let productID: Int
    let name: String
    let vendor: String
    let locationID: UInt32

    var bus: UInt32 { locationID >> 24 }
    var isDockDevice: Bool { DockClassifier.isDockDevice(vendorID: vendorID, name: name) }
}

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isActive: Bool
    let width: Int
    let height: Int
}

enum DockClassifier {
    static let displayLinkVendorID = 0x17E9
    static let dellVendorID = 0x413C

    static func isDockDevice(vendorID: Int, name: String) -> Bool {
        if vendorID == displayLinkVendorID { return true }
        if name.localizedCaseInsensitiveContains("D6000") { return true }
        return vendorID == dellVendorID && name.localizedCaseInsensitiveContains("dock")
    }
}

enum DockHealth: Equatable {
    case dockNotDetected
    case agentNotInstalled
    case agentNotRunning
    case noMonitors
    case healthy(monitors: Int)

    var title: String {
        switch self {
        case .dockNotDetected: String(localized: "Dock not detected")
        case .agentNotInstalled: String(localized: "DisplayLink Manager is not installed")
        case .agentNotRunning: String(localized: "DisplayLink Manager is closed")
        case .noMonitors: String(localized: "Dock connected, no monitors")
        case .healthy(let monitors): monitors == 1 ? String(localized: "Dock ready, 1 monitor") : String(localized: "Dock ready, \(monitors) monitors")
        }
    }

    var detail: String {
        switch self {
        case .dockNotDetected: String(localized: "macOS can't see the dock over USB. Check the cable and the dock's power.")
        case .agentNotInstalled: String(localized: "The dock's monitors can't work without this program.")
        case .agentNotRunning: String(localized: "The dock's monitors need this program open. Click Restart DisplayLink.")
        case .noMonitors: String(localized: "Try Restart DisplayLink. If nothing changes, use Reset Dock USB.")
        case .healthy: String(localized: "Everything is responding normally.")
        }
    }

    var symbolName: String {
        switch self {
        case .dockNotDetected: "display"
        case .agentNotInstalled, .agentNotRunning, .noMonitors: "display.trianglebadge.exclamationmark"
        case .healthy: "display.2"
        }
    }
}

struct DockSnapshot: Equatable {
    var usbDevices: [USBDevice] = []
    var displays: [DisplayInfo] = []
    var agentInstalled = false
    var agentRunning = false

    var dockDevices: [USBDevice] { usbDevices.filter(\.isDockDevice) }
    var externalDisplays: [DisplayInfo] { displays.filter { !$0.isBuiltin } }

    func isBehindDock(_ device: USBDevice) -> Bool {
        !device.isDockDevice && dockDevices.contains { $0.bus == device.bus }
    }

    var health: DockHealth {
        if dockDevices.isEmpty { return .dockNotDetected }
        if !agentInstalled { return .agentNotInstalled }
        if !agentRunning { return .agentNotRunning }
        if externalDisplays.isEmpty { return .noMonitors }
        return .healthy(monitors: externalDisplays.count)
    }

    func changes(since old: DockSnapshot) -> [String] {
        var events: [String] = []
        let oldUSB = Set(old.usbDevices)
        let newUSB = Set(usbDevices)
        events += newUSB.subtracting(oldUSB).map { String(localized: "Connected: \($0.name)") }.sorted()
        events += oldUSB.subtracting(newUSB).map { String(localized: "Disconnected: \($0.name)") }.sorted()

        let oldDisplayIDs = Set(old.displays.map(\.id))
        let newDisplayIDs = Set(displays.map(\.id))
        events += displays.filter { !oldDisplayIDs.contains($0.id) }.map { String(localized: "Monitor added: \($0.name)") }
        events += old.displays.filter { !newDisplayIDs.contains($0.id) }.map { String(localized: "Monitor removed: \($0.name)") }

        if agentRunning != old.agentRunning {
            events.append(agentRunning ? String(localized: "DisplayLink Manager opened") : String(localized: "DisplayLink Manager closed"))
        }
        return events
    }
}

struct LogEvent: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}
