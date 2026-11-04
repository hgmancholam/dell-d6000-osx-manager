import SwiftUI

@main
struct D6000MenuApp: App {
    @StateObject private var store = DockStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Image(systemName: store.snapshot.health.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
