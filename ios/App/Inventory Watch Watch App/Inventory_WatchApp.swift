//
//  Inventory_WatchApp.swift
//  Inventory Watch Watch App
//
//  Created by יוסף דנה on 21/10/2026.
//

import SwiftUI

@main
struct Inventory_Watch_Watch_AppApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}
