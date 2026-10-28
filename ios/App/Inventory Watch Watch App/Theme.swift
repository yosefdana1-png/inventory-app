//
//  Theme.swift
//  Inventory Watch Watch App
//

import SwiftUI

/// Calm dark palette shared with the iPhone app: neutral surfaces and one gold accent.
enum Theme {
    static let background = Color(hex: 0x0F1012)
    static let surface = Color(hex: 0x17181B)
    static let surfacePressed = Color(hex: 0x1D1F22)
    static let border = Color(hex: 0x26282C)

    static let text = Color(hex: 0xECE9E2)
    static let secondaryText = Color(hex: 0xA3A099)
    static let mutedText = Color(hex: 0x6F6D69)

    /// The single accent, for the main action and small highlights only.
    static let accent = Color(hex: 0xC6A15B)
    /// Text or icons drawn on top of the accent.
    static let onAccent = Color(hex: 0x0F1012)

    // Status colours — only where they carry meaning.
    static let outOfStock = Color(hex: 0xC4685C)
    static let lowStock = Color(hex: 0xC98B4E)

    static let cornerRadius: CGFloat = 8

    /// Quantity color: normal text, low-stock orange at or below the low-stock level,
    /// out-of-stock red at zero. Only applies when the warehouse enables low-stock alerts.
    static func quantityColor(for item: Item, settings: WarehouseSettings) -> Color {
        guard settings.showLowStock, let lowStock = item.lowStock else { return text }
        if item.quantity == 0 { return outOfStock }
        if item.quantity <= lowStock { return Theme.lowStock }
        return text
    }
}

/// List row background: a surface card with a thin border.
struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

/// Neutral button: surface background, text-coloured content, darker when pressed.
struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.text)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(configuration.isPressed ? Theme.surfacePressed : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

/// Main action: gold background with dark text.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.accent)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
