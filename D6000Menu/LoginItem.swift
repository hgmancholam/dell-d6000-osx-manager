import Foundation
import ServiceManagement

enum LoginItem {
    private static let didAutoEnableKey = "didAutoEnableLoginItem"

    static var isInstalled: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    // Runs once so that turning the option off later is respected on the next launch.
    static func enableOnFirstInstalledLaunch() throws {
        guard isInstalled, !UserDefaults.standard.bool(forKey: didAutoEnableKey) else { return }
        try SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: didAutoEnableKey)
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
