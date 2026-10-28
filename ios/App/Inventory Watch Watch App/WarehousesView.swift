//
//  WarehousesView.swift
//  Inventory Watch Watch App
//

import SwiftUI

struct WarehousesView: View {
    @Environment(AppModel.self) private var model

    @State private var isLoading = false
    @State private var errorText: String?
    @State private var confirmLogout = false

    var body: some View {
        List {
            if let displayName = model.displayName {
                Text(displayName)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.lowStock)
                    .listRowBackground(Color.clear)
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Theme.outOfStock)
                    .listRowBackground(Color.clear)
            }

            if let warehouses = model.warehouses {
                if warehouses.isEmpty {
                    Text("אין מחסנים")
                        .foregroundStyle(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                }
                ForEach(warehouses) { warehouse in
                    NavigationLink(value: warehouse) {
                        Text(warehouse.name)
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                    }
                    .listRowBackground(CardBackground())
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            NavigationLink(value: AccountsRoute()) {
                Label("החלף חשבון", systemImage: "person.2")
                    .foregroundStyle(Theme.text)
            }
            .listRowBackground(CardBackground())

            Button(role: .destructive) {
                confirmLogout = true
            } label: {
                Label("התנתק", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .foregroundStyle(Theme.outOfStock)
            .listRowBackground(CardBackground())
        }
        .navigationTitle("מחסנים")
        .containerBackground(Theme.background, for: .navigation)
        .toolbar {
            // Top bar next to the title; the bottom bar floated over the list rows.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.surfacePressed)
                .accessibilityLabel("רענן")
                .disabled(isLoading)
            }
        }
        .refreshable { await refresh() }
        .confirmationDialog("להתנתק מהחשבון?", isPresented: $confirmLogout) {
            Button("התנתק", role: .destructive) { Task { await model.signOut() } }
            Button("ביטול", role: .cancel) {}
        }
        .task {
            // Cached list shows instantly; it is refreshed in the background.
            await refresh()
        }
    }

    private func refresh() async {
        isLoading = true
        do {
            try await model.refreshWarehouses()
            errorText = nil
        } catch {
            errorText = model.handle(error)
        }
        isLoading = false
    }
}
