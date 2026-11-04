import AppKit
import CoreGraphics
import IOKit

enum HardwareScanner {
    static let agentBundleID = "com.displaylink.DisplayLinkUserAgent"

    static func snapshot() -> DockSnapshot {
        DockSnapshot(
            usbDevices: usbDevices(),
            displays: displays(),
            agentInstalled: NSWorkspace.shared.urlForApplication(withBundleIdentifier: agentBundleID) != nil,
            agentRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).isEmpty
        )
    }

    static func usbDevices() -> [USBDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [USBDevice] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }

            let vendorID: Int = property(service, "idVendor") ?? 0
            let productID: Int = property(service, "idProduct") ?? 0
            let name: String = property(service, "USB Product Name")
                ?? property(service, "kUSBProductString")
                ?? String(format: String(localized: "Device %04X:%04X"), vendorID, productID)
            let vendor: String = property(service, "USB Vendor Name") ?? property(service, "kUSBVendorString") ?? ""
            let location: Int = property(service, "locationID") ?? 0

            devices.append(USBDevice(
                id: registryID,
                vendorID: vendorID,
                productID: productID,
                name: name,
                vendor: vendor,
                locationID: UInt32(truncatingIfNeeded: location)
            ))
        }
        return devices.sorted { $0.locationID < $1.locationID }
    }

    static func displays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }

        return ids.prefix(Int(count)).map { id in
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            return DisplayInfo(
                id: id,
                name: names[id] ?? (isBuiltin ? String(localized: "Built-in display") : String(localized: "Monitor \(String(id))")),
                isBuiltin: isBuiltin,
                isActive: CGDisplayIsActive(id) != 0,
                width: CGDisplayPixelsWide(id),
                height: CGDisplayPixelsHigh(id)
            )
        }
    }

    private static func property<T>(_ service: io_service_t, _ key: String) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
    }
}
