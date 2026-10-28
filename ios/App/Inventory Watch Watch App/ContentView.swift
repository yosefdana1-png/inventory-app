//
//  ContentView.swift
//  Inventory Watch Watch App
//

import SwiftUI

/// Root: the login screen without a saved session, otherwise the warehouse list.
///
/// Right-to-left is forced on each screen's content rather than on the
/// NavigationStack itself: the system clock does not follow the forced direction,
/// so flipping the navigation bar puts the Back button underneath the clock.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        screens
            // Becoming active re-checks this watch's "connected devices" entry
            // (signs out if it was disconnected elsewhere) and runs the heartbeat.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    Task { await model.appDidBecomeActive() }
                } else {
                    model.appDidResignActive()
                }
            }
    }

    @ViewBuilder
    private var screens: some View {
        if model.isLoggedIn {
            NavigationStack {
                WarehousesView()
                    .rightToLeft()
                    .navigationDestination(for: Warehouse.self) { warehouse in
                        ItemsView(warehouse: warehouse)
                            .rightToLeft()
                    }
                    .navigationDestination(for: ItemRoute.self) { route in
                        ItemView(warehouseID: route.warehouseID, item: route.item)
                            .rightToLeft()
                    }
                    .navigationDestination(for: AccountsRoute.self) { _ in
                        AccountsView()
                            .rightToLeft()
                    }
            }
            // Another account becoming active ("החלף חשבון", or "חבר את השעון לחשבון הזה"
            // on the iPhone) starts from its warehouse list.
            .id(model.sessionID)
        } else {
            LoginView()
                .rightToLeft()
        }
    }
}

private extension View {
    func rightToLeft() -> some View {
        environment(\.layoutDirection, .rightToLeft)
    }
}
