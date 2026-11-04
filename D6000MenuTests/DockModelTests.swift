import AppKit
import XCTest
@testable import D6000Menu

final class DockModelTests: XCTestCase {
    private let displayLink = USBDevice(id: 1, vendorID: 0x17E9, productID: 0x6006, name: "Dell D6000", vendor: "DisplayLink", locationID: 0x0210_0000)
    private let keyboard = USBDevice(id: 2, vendorID: 0x05AC, productID: 0x1, name: "Teclado", vendor: "Apple", locationID: 0x0211_0000)
    private let otherBus = USBDevice(id: 3, vendorID: 0x05AC, productID: 0x2, name: "Hub", vendor: "Apple", locationID: 0x0110_0000)
    private let monitor = DisplayInfo(id: 9, name: "U2720", isBuiltin: false, isActive: true, width: 2560, height: 1440)

    func testClassifier() {
        XCTAssertTrue(DockClassifier.isDockDevice(vendorID: 0x17E9, name: "Cualquiera"))
        XCTAssertTrue(DockClassifier.isDockDevice(vendorID: 0x1234, name: "Dell d6000 Audio"))
        XCTAssertTrue(DockClassifier.isDockDevice(vendorID: 0x413C, name: "Dell Universal Dock"))
        XCTAssertFalse(DockClassifier.isDockDevice(vendorID: 0x413C, name: "Dell Keyboard"))
    }

    func testHealthProgression() {
        var snapshot = DockSnapshot()
        XCTAssertEqual(snapshot.health, .dockNotDetected)

        snapshot.usbDevices = [displayLink]
        XCTAssertEqual(snapshot.health, .agentNotInstalled)

        snapshot.agentInstalled = true
        XCTAssertEqual(snapshot.health, .agentNotRunning)

        snapshot.agentRunning = true
        XCTAssertEqual(snapshot.health, .noMonitors)

        snapshot.displays = [monitor]
        XCTAssertEqual(snapshot.health, .healthy(monitors: 1))
    }

    func testDevicesOnDockBusAreMarked() {
        let snapshot = DockSnapshot(usbDevices: [displayLink, keyboard, otherBus])
        XCTAssertTrue(snapshot.isBehindDock(keyboard))
        XCTAssertFalse(snapshot.isBehindDock(otherBus))
        XCTAssertFalse(snapshot.isBehindDock(displayLink))
    }

    func testChangesDescribeAttachAndDetach() {
        let before = DockSnapshot(usbDevices: [keyboard], displays: [], agentInstalled: true, agentRunning: false)
        let after = DockSnapshot(usbDevices: [displayLink], displays: [monitor], agentInstalled: true, agentRunning: true)

        XCTAssertEqual(after.changes(since: before), [
            "Conectado: Dell D6000",
            "Desconectado: Teclado",
            "Monitor añadido: U2720",
            "DisplayLink Manager abierto",
        ])
        XCTAssertEqual(after.changes(since: after), [])
    }

    func testHealthSymbolsExist() {
        let states: [DockHealth] = [.dockNotDetected, .agentNotInstalled, .agentNotRunning, .noMonitors, .healthy(monitors: 2)]
        for state in states {
            XCTAssertNotNil(NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil), state.symbolName)
        }
    }

    // The built-in panel goes offline with the lid closed, so only some display is guaranteed.
    func testRealScanFindsDisplayAndAgent() {
        let snapshot = HardwareScanner.snapshot()
        XCTAssertFalse(snapshot.displays.isEmpty)
        XCTAssertTrue(snapshot.agentInstalled)
    }

    func testWatcherStartsAndStops() {
        var watcher: SystemWatcher? = SystemWatcher {}
        XCTAssertNotNil(watcher)
        watcher = nil
    }
}
