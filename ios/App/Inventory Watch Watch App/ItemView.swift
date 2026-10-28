//
//  ItemView.swift
//  Inventory Watch Watch App
//

import SwiftUI
import WatchKit

/// Quantity editor. Taps and crown steps build up a pending amount; after
/// 1.5 seconds without input the total is sent as one update (one history line).
struct ItemView: View {
    @Environment(AppModel.self) private var model
    let warehouseID: String
    let item: Item

    /// Last known saved quantity (optimistic while a save is in flight).
    @State private var quantity: Int
    @State private var pending = 0
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var commitTask: Task<Void, Never>?
    @State private var crownValue = 0.0
    @State private var lastCrownStep = 0

    private static let commitDelay: Duration = .seconds(1.5)

    init(warehouseID: String, item: Item) {
        self.warehouseID = warehouseID
        self.item = item
        _quantity = State(initialValue: item.quantity)
    }

    private var shownQuantity: Int { max(0, quantity + pending) }

    private var quantityColor: Color {
        var current = item
        current.quantity = shownQuantity
        return Theme.quantityColor(for: current, settings: model.settings[warehouseID] ?? WarehouseSettings())
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(item.name)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)

            Text("\(shownQuantity)")
                .font(.system(size: 50, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(quantityColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: shownQuantity)

            statusLine
                .font(.footnote.weight(.semibold))
                .frame(height: 18)

            HStack(spacing: 10) {
                stepButton(symbol: "plus", label: "הוספה") { adjust(by: 1) }
                stepButton(symbol: "minus", label: "הורדה") { adjust(by: -1) }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .containerBackground(Theme.background, for: .navigation)
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: -100_000, through: 100_000, by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            let step = Int(newValue.rounded())
            let diff = step - lastCrownStep
            lastCrownStep = step
            if diff != 0 { adjust(by: diff, playHaptic: false) }
        }
        .task { await loadFreshQuantity() }
        .onDisappear {
            // Leaving the screen saves any pending amount right away. The amount is
            // captured now because this view's state is gone once it disappears.
            commitTask?.cancel()
            let amount = pending
            guard amount != 0 else { return }
            pending = 0
            Task { [model, warehouseID, itemID = item.id] in
                do {
                    _ = try await model.changeQuantity(warehouseID: warehouseID, itemID: itemID, by: amount)
                    WKInterfaceDevice.current().play(.success)
                } catch {
                    model.handle(error)
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if pending != 0 {
            Text(pending > 0 ? "+\(pending)" : "−\(-pending)")
                .foregroundStyle(Theme.accent)
        } else if isSaving {
            Text("שומר…").foregroundStyle(Theme.secondaryText)
        } else if let errorText {
            Text(errorText).foregroundStyle(Theme.outOfStock).lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Text(" ")
        }
    }

    private func stepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(SurfaceButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Pending amount

    private func adjust(by step: Int, playHaptic: Bool = true) {
        // Removing can't go below zero, so the pending amount is clamped here too.
        let newPending = max(pending + step, -quantity)
        guard newPending != pending else { return }
        pending = newPending
        errorText = nil
        if playHaptic { WKInterfaceDevice.current().play(.click) }

        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            await commit()
        }
    }

    private func commit() async {
        // Saves run one at a time so a failure restores the right number.
        while isSaving {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let amount = pending
        guard amount != 0 else { return }
        pending = 0

        let previous = quantity
        quantity = max(0, quantity + amount)
        isSaving = true
        do {
            quantity = try await model.changeQuantity(warehouseID: warehouseID, itemID: item.id, by: amount)
            WKInterfaceDevice.current().play(.success)
        } catch {
            quantity = previous
            model.handle(error)
            if case AppError.itemMissing = error {
                errorText = AppError.itemMissing.localizedDescription
            } else {
                errorText = "לא נשמר — נסה שוב"
            }
            WKInterfaceDevice.current().play(.failure)
        }
        isSaving = false
    }

    private func loadFreshQuantity() async {
        guard let fresh = try? await model.freshQuantity(warehouseID: warehouseID, itemID: item.id),
              pending == 0, !isSaving else { return }
        quantity = fresh
    }
}
