//
//  ItemsView.swift
//  Inventory Watch Watch App
//

import SwiftUI

struct ItemsView: View {
    @Environment(AppModel.self) private var model
    let warehouse: Warehouse

    @State private var search = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private var settings: WarehouseSettings { model.settings[warehouse.id] ?? WarehouseSettings() }

    private var filteredItems: [Item]? {
        model.items[warehouse.id]?.filter { $0.matches(search) }
    }

    var body: some View {
        List {
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Theme.outOfStock)
                    .listRowBackground(Color.clear)
            }

            if let items = filteredItems {
                if items.isEmpty {
                    Text(search.isEmpty ? "אין פריטים" : "לא נמצאו פריטים")
                        .foregroundStyle(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                }
                ForEach(items) { item in
                    NavigationLink(value: ItemRoute(warehouseID: warehouse.id, item: item)) {
                        HStack {
                            Text(item.name)
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Text("\(item.quantity)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(Theme.quantityColor(for: item, settings: settings))
                        }
                    }
                    .listRowBackground(CardBackground())
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(warehouse.name)
        .containerBackground(Theme.background, for: .navigation)
        .searchable(text: $search, prompt: "חיפוש")
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        do {
            try await model.refreshItems(in: warehouse.id)
            errorText = nil
        } catch {
            errorText = model.handle(error)
        }
        isLoading = false
    }
}

/// Navigation value for the item screen.
struct ItemRoute: Hashable {
    let warehouseID: String
    let item: Item
}
