import AppKit
import CoreGraphics
import IOKit
import os

final class SystemWatcher {
    private let onChange: () -> Void
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        startUSB()
        startDisplays()
        startWorkspace()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(Self.displayCallback, Unmanaged.passUnretained(self).toOpaque())
        iterators.forEach { IOObjectRelease($0) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private static let logger = Logger(subsystem: "com.hgmancholam.D6000Menu", category: "watcher")

    private static let usbCallback: IOServiceMatchingCallback = { context, iterator in
        logger.notice("usb notification")
        drain(iterator)
        guard let context else { return }
        Unmanaged<SystemWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
    }

    private static let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag), let context else { return }
        Unmanaged<SystemWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
    }

    // IOKit stops delivering notifications until each iterator has been read to the end.
    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            IOObjectRelease(service)
        }
    }

    private func startUSB() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("IOUSBHostDevice"), Self.usbCallback, context, &iterator)
            guard result == KERN_SUCCESS else { continue }
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private func startDisplays() {
        CGDisplayRegisterReconfigurationCallback(Self.displayCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    private func startWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange()
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == HardwareScanner.agentBundleID {
                    self?.onChange()
                }
            })
        }
    }
}
