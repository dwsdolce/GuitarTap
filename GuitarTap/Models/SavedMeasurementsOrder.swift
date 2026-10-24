//
//  SavedMeasurementsOrder.swift
//  GuitarTap
//
//  The order Saved Measurements shows the library in: its sort, direction and type filter. The library keeps
//  the order measurements were added, and sorting or filtering never changes it — they decide only which
//  measurements the list shows and in what order, so As Added is always there to return to. And which of the
//  library's entries are duplicates, for Delete Duplicates.
//
// @parity model/saved-measurements-order tests=test/saved-measurements-order

import Foundation

/// How Saved Measurements is sorted.
enum SavedMeasurementsSort: String, CaseIterable, Identifiable {
    case asAdded, date, name, type

    var id: String { rawValue }

    /// The menu's word for it.
    var title: String {
        switch self {
        case .asAdded: return "As Added"
        case .date: return "Date"
        case .name: return "Name"
        case .type: return "Type"
        }
    }
}

enum SavedMeasurementsOrder {
    /// What the order needs of one measurement: its name, the date it was made, and the type the list shows
    /// (``TapToneMeasurement/measurementTypeShortName``).
    struct Key {
        let name: String
        let date: Date
        let type: String
    }

    /// The types the filter offers: the type menu's, in its order, then Comparison.
    static let filterTypes: [String] = MeasurementType.allCases.map(\.shortName) + ["Comparison"]

    static func keys(_ measurements: [TapToneMeasurement]) -> [Key] {
        measurements.map { Key(name: $0.measurementName ?? "", date: $0.timestamp, type: $0.measurementTypeShortName) }
    }

    /// The positions in the library to show, in order: those of the `filter` type (all when `nil`), sorted by
    /// `sort` in the given direction. Ties go by date, oldest first, then by position. Names compare
    /// case-insensitively; type order is the filter's, then a type it does not name ("—").
    static func shown(_ keys: [Key], sort: SavedMeasurementsSort, ascending: Bool, filter: String?) -> [Int] {
        func rank(_ type: String) -> Int { filterTypes.firstIndex(of: type) ?? filterTypes.count }
        func primary(_ a: Int, _ b: Int) -> Int {
            switch sort {
            case .asAdded: return compare(a, b)
            case .date: return compare(keys[a].date, keys[b].date)
            case .name: return compare(keys[a].name.lowercased(), keys[b].name.lowercased())
            case .type: return compare(rank(keys[a].type), rank(keys[b].type))
            }
        }
        return keys.indices
            .filter { filter == nil || keys[$0].type == filter }
            .sorted { a, b in
                let byKey = primary(a, b) * (ascending ? 1 : -1)
                if byKey != 0 { return byKey < 0 }
                let byDate = compare(keys[a].date, keys[b].date)
                if byDate != 0 { return byDate < 0 }
                return a < b
            }
    }

    /// The positions of the library's duplicates: each entry whose id an earlier entry already has (ids compare
    /// case-insensitively). The first copy of each stays. Same id means same content — an edited measurement gets a
    /// new id — so a duplicate is an exact copy, such as a second import of the same file.
    static func duplicates(_ ids: [String]) -> [Int] {
        var seen = Set<String>()
        return ids.indices.filter { !seen.insert(ids[$0].lowercased()).inserted }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> Int { a < b ? -1 : (a > b ? 1 : 0) }
}
