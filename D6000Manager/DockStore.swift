import Foundation
import os

@MainActor
final class DockStore: ObservableObject {
    @Published private(set) var snapshot = DockSnapshot()
    @Published private(set) var events: [LogEvent] = []
    @Published private(set) var runningAction: String?
    @Published private(set) var lastResult: String?
    @Published private(set) var lastScan = Date()
    @Published private(set) var opensAtLogin = false

    private let logger = Logger(subsystem: "com.hgmancholam.D6000Menu", category: "store")
    private var watcher: SystemWatcher?
    private var pendingRefresh: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init() {
        snapshot = HardwareScanner.snapshot()
        logger.notice("start dock=\(self.snapshot.dockDevices.count) displays=\(self.snapshot.displays.count)")
        do {
            try LoginItem.enableOnFirstInstalledLaunch()
        } catch {
            lastResult = String(localized: "Could not enable automatic startup: \(error.localizedDescription)")
        }
        syncLoginItem()
        watcher = SystemWatcher { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.refreshNow()
            }
        }
    }

    func refreshNow() {
        let new = HardwareScanner.snapshot()
        let changes = new.changes(since: snapshot)
        snapshot = new
        let date = Date()
        lastScan = date
        guard !changes.isEmpty else { return }
        logger.notice("changed dock=\(new.dockDevices.count) displays=\(new.displays.count) events=\(changes.count)")
        events = Array((changes.map { LogEvent(date: date, text: $0) } + events).prefix(5))
    }

    func syncLoginItem() {
        let status = LoginItem.status
        opensAtLogin = status == .enabled
        logger.notice("loginItem status=\(status.rawValue)")
        if status == .requiresApproval {
            lastResult = String(localized: "Authorize D6000 Manager in System Settings > General > Login Items.")
        }
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled: enabled)
        } catch {
            lastResult = String(localized: "Could not change automatic startup: \(error.localizedDescription)")
        }
        syncLoginItem()
    }

    func restartDisplayLink() {
        run(String(localized: "Restarting DisplayLink…")) { await DockActions.restartDisplayLink() }
    }

    func reconfigureDisplays() {
        run(String(localized: "Reconfiguring monitors…")) { DockActions.reconfigureDisplays() }
    }

    func resetUSB() {
        let devices = snapshot.dockDevices
        run(String(localized: "Resetting dock USB…")) { await DockActions.resetUSB(devices: devices) }
    }

    // A dock attach fires many USB notifications in a burst, so they collapse into one scan.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            refreshNow()
        }
    }

    private func run(_ label: String, _ action: @escaping () async -> String) {
        guard runningAction == nil else { return }
        runningAction = label
        Task {
            let result = await action()
            lastResult = result
            runningAction = nil
            refreshNow()
        }
    }
}
