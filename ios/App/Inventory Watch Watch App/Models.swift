//
//  Models.swift
//  Inventory Watch Watch App
//

import Foundation

struct Warehouse: Identifiable, Hashable {
    let id: String
    var name: String
    /// The value stored under `users/{username}/warehouses/{id}`, used for ordering.
    var order: Double
}

struct Item: Identifiable, Hashable {
    let id: String
    var name: String
    var quantity: Int
    var order: Double
    var sku: String?
    var lowStock: Int?
    var note: String?

    /// Builds an item from the raw Realtime Database JSON. `history` is ignored.
    init?(id: String, json: Any) {
        guard let dict = json as? [String: Any] else { return nil }
        self.id = id
        name = JSONValue.string(dict["name"]) ?? ""
        quantity = max(0, JSONValue.int(dict["quantity"]) ?? 0)
        order = JSONValue.double(dict["order"]) ?? .greatestFiniteMagnitude
        sku = JSONValue.string(dict["sku"])
        lowStock = JSONValue.int(dict["lowStock"])
        note = JSONValue.string(dict["note"])
    }

    /// True when the search text appears in the name, SKU or note (case-insensitive).
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return [name, sku, note].contains { $0?.lowercased().contains(q) == true }
    }
}

struct WarehouseSettings: Hashable {
    var showLowStock = false
    var sortByName = false
}

/// Lenient readers for JSON values: the web app may store numbers as strings or doubles.
enum JSONValue {
    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        double(value).map { Int($0) }
    }
}
