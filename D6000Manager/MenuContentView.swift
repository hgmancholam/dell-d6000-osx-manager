import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: DockStore
    @State private var confirmingUSBReset = false

    private var snapshot: DockSnapshot { store.snapshot }
    private var isBusy: Bool { store.runningAction != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    displaysSection
                    usbSection
                    eventsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Inside a MenuBarExtra window a ScrollView collapses unless its height is fixed.
            .frame(height: 340)
            Divider()
            actions
            resultLine
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
        // onAppear fires only on the first open of a MenuBarExtra window.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.refreshNow()
            store.syncLoginItem()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: snapshot.health.symbolName)
                .font(.title2)
                .foregroundStyle(headerColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.health.title).font(.headline)
                Text(snapshot.health.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerColor: Color {
        if case .healthy = snapshot.health { return .green }
        return snapshot.health == .dockNotDetected ? .secondary : .orange
    }

    private var displaysSection: some View {
        section("Monitors") {
            ForEach(snapshot.displays) { display in
                row(
                    title: display.name,
                    detail: display.isActive
                        ? String(localized: "\(String(display.width)) × \(String(display.height))")
                        : String(localized: "\(String(display.width)) × \(String(display.height)), inactive"),
                    badge: display.isBuiltin ? String(localized: "Built-in") : String(localized: "External")
                )
            }
        }
    }

    private var usbSection: some View {
        section("USB Devices") {
            if snapshot.usbDevices.isEmpty {
                Text("macOS reports no USB devices.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(snapshot.usbDevices) { device in
                row(
                    title: device.name,
                    detail: String(format: "%04X:%04X %@", device.vendorID, device.productID, device.vendor),
                    badge: device.isDockDevice
                        ? String(localized: "Dock")
                        : (snapshot.isBehindDock(device) ? String(localized: "On the dock") : nil)
                )
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if !store.events.isEmpty {
            section("Recent Changes") {
                ForEach(store.events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.date, style: .time).foregroundStyle(.secondary).monospacedDigit()
                        Text(event.text)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Refresh") { store.refreshNow() }
                Button("Restart DisplayLink") { store.restartDisplayLink() }
                    .keyboardShortcut(.defaultAction)
                Button("Reapply Mode") { store.reconfigureDisplays() }
                    .disabled(snapshot.externalDisplays.isEmpty)
                    .help("Reapplies the current resolution to the external monitors macOS already sees.")
            }
            .controlSize(.small)

            if confirmingUSBReset {
                Text("DisplayLink will close, and the dock's monitors, audio and network will cut out for a few seconds. Eject any drives connected to it first.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Reset USB Now", role: .destructive) {
                        confirmingUSBReset = false
                        store.resetUSB()
                    }
                    Button("Cancel") { confirmingUSBReset = false }
                }
                .controlSize(.small)
            } else {
                Button("Reset Dock USB…") { confirmingUSBReset = true }
                    .controlSize(.small)
                    .disabled(snapshot.dockDevices.isEmpty)
            }
        }
        .disabled(isBusy)
    }

    @ViewBuilder
    private var resultLine: some View {
        if let text = store.runningAction ?? store.lastResult {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open at Login", isOn: Binding(
                get: { store.opensAtLogin },
                set: { store.setOpensAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(!LoginItem.isInstalled)
            statusLine
        }
    }

    private var statusLine: some View {
        HStack {
            Text("Last read: \(store.lastScan.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func row(title: String, detail: String, badge: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let badge {
                Text(badge).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
