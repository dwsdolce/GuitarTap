//
//  ImportPersistenceTests.swift
//  GuitarTapTests
//
//  The saved-measurement library: importing through the app's import (`importAndLoadMeasurements`),
//  editing an entry, saving, and the message an import shows. The shared cases in
//  `import-persistence.json` (IP1–IP9, IM1–IM3), the same as Python and the web; IP8 is the web's alone.
//
//  Each case gives its analyzer a library file of its own, so neither the user's measurements nor another
//  suite's saves running in parallel can reach it.
//
// @parity test/import-persistence

import Testing
import Foundation
@testable import GuitarTap

private final class ImportPersistenceAnchor {}

@Suite("ImportPersistence", .serialized)
@MainActor
struct ImportPersistenceTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ImportPersistenceAnchor.self).url(forResource: "import-persistence", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static var measurements: [String: [String: Any]] { data["measurements"] as! [String: [String: Any]] }

    /// The cases for the natives: all but those marked for the web alone.
    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).filter { $0["only"] as? String != "web" }.map { $0["id"] as! String }
    }

    /// The names the library file holds once every write made so far has landed (nil if unreadable).
    static func persistedNames(in file: URL) -> [String]? {
        TapToneAnalyzer.persistQueue.sync {}
        guard let fileData = try? Data(contentsOf: file),
              let decoded = try? TapToneAnalyzer.decodeMeasurements(fileData) else { return nil }
        return decoded.map { $0.measurementName ?? "" }
    }

    @Test(arguments: ids())
    func library(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let sut = TapToneAnalyzer.forTesting()
        sut.savedMeasurements = []
        sut.libraryFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-persistence-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sut.libraryFileURL) }
        var message: String?
        for step in row["steps"] as! [[String: Any]] {
            if let names = step["import"] as? [String] {
                let file = try JSONSerialization.data(withJSONObject: names.map { Self.measurements[$0]! })
                message = try sut.importAndLoadMeasurements(from: file)
            } else if let edit = step["edit"] as? [String: Any] {
                sut.updateMeasurement(at: edit["entry"] as! Int,
                                      measurementName: edit["name"] as? String,
                                      notes: edit["notes"] as? String)
            } else if let name = step["save"] as? String {
                sut.saveMeasurement(measurementName: name)
            } else if step["deleteAll"] as? Bool == true {
                sut.deleteAllMeasurements()
            } else if let warning = step["warning"] as? String {
                sut.microphoneWarning = warning
            }
        }

        let library = sut.savedMeasurements
        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "library":
                #expect(library.map { $0.measurementName ?? "" } == want as! [String], "\(id) \(field)")
            case "notes":
                let wantNotes = (want as! [Any]).map { $0 as? String }
                #expect(library.map(\.notes) == wantNotes, "\(id) \(field)")
            case "persisted":
                let persisted = Self.persistedNames(in: sut.libraryFileURL)
                #expect(persisted == want as? [String], "\(id) \(field): \(String(describing: persisted))")
            case "ids":
                let fileIDs = Self.measurements.mapValues { $0["id"] as! String }
                let want = want as! [String]
                #expect(library.count == want.count, "\(id) \(field): count")
                for (entry, name) in zip(library, want) {
                    let actual = entry.id.uuidString
                    if name == "new" {
                        #expect(!fileIDs.values.contains(actual), "\(id) \(field): a new id, not a file's")
                    } else {
                        #expect(actual == fileIDs[name], "\(id) \(field): \(name)'s own id")
                    }
                }
            case "message":
                #expect(message == want as? String, "\(id) \(field): \(String(describing: message))")
            case "messageStartsWith":
                #expect(message?.hasPrefix(want as! String) == true, "\(id) \(field): \(String(describing: message))")
            case "microphoneWarning":
                #expect((sut.microphoneWarning != nil) == want as? Bool, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }
}
