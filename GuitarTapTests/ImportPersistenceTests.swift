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
            } else if let names = step["importFails"] as? [String] {
                let file = try JSONSerialization.data(withJSONObject: names.map { Self.measurements[$0]! })
                do {
                    _ = try sut.importAndLoadMeasurements(from: file)
                    Issue.record("\(id): the import fails")
                } catch {
                    if let want = step["message"] as? String {
                        let got = TapToneAnalyzer.importErrorMessage(for: error, fileName: step["file"] as! String)
                        #expect(got == want, "\(id): message \(got)")
                    }
                }
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
            } else {
                Issue.record("\(id): unknown step \(step)")
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
                let fileIDs = Self.measurements.compactMapValues { $0["id"] as? String }
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

    // MARK: - A library that cannot be read

    /// The shared measurement a whole library holds that makes it unreadable.
    nonisolated static let unreadableMeasurement = ["bad id": "bad-id", "no spectrum": "no-spectrum", "empty spectrum": "empty-spectrum"]
    nonisolated static let unreadableKinds = ["cut short", "bad id", "no spectrum", "empty spectrum"]

    /// A library that cannot be read: one cut short mid-write, or whole but holding an id that is not a UUID
    /// or a measurement with no spectrum, or one whose spectrum has no points.
    static func unreadableLibrary(_ kind: String) throws -> Data {
        if let name = unreadableMeasurement[kind] {
            return try JSONSerialization.data(withJSONObject: [measurements[name]!])
        }
        let whole = try JSONSerialization.data(withJSONObject: [measurements.values.first!])
        return whole.prefix(whole.count / 2)
    }

    /// The library could not be read: it is kept beside itself, renamed, the library starts empty and the
    /// user is told; the next save writes a new library and leaves the kept one as it was.
    @Test(arguments: unreadableKinds)
    func unreadableLibrary_isKeptAsideAndNotWrittenOver(_ kind: String) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("unreadable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = dir.appendingPathComponent("saved_measurements.json")
        let damaged = try Self.unreadableLibrary(kind)
        try damaged.write(to: library)

        let sut = TapToneAnalyzer.forTesting()
        sut.savedMeasurements = []
        sut.libraryFileURL = library
        sut.loadPersistedMeasurements()

        #expect(sut.savedMeasurements.isEmpty)
        #expect(sut.libraryLoadFailure?.contains("saved_measurements-unreadable-") == true)
        let kept = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("saved_measurements-unreadable-") }
        try #require(kept.count == 1)
        #expect(try Data(contentsOf: kept[0]) == damaged, "kept as it was")

        let file = try JSONSerialization.data(withJSONObject: [Self.measurements["A"]!])
        _ = try sut.importAndLoadMeasurements(from: file)
        TapToneAnalyzer.persistQueue.sync {}
        #expect(Self.persistedNames(in: library)?.count == 1, "a new library is written")
        #expect(try Data(contentsOf: kept[0]) == damaged, "and the kept one is not touched")
    }

    /// The library could not be read and could not be renamed (its folder is read-only): it stays where
    /// it is, the user is told, and nothing is written over it this session.
    @Test(arguments: unreadableKinds)
    func unreadableLibrary_thatCannotBeMoved_isNotWritten(_ kind: String) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("unreadable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let library = dir.appendingPathComponent("saved_measurements.json")
        let damaged = try Self.unreadableLibrary(kind)
        try damaged.write(to: library)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.savedMeasurements = []
        sut.libraryFileURL = library
        sut.loadPersistedMeasurements()
        #expect(sut.libraryLoadFailure != nil)
        #expect(sut.isLibraryWriteBlocked)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        let file = try JSONSerialization.data(withJSONObject: [Self.measurements["A"]!])
        _ = try sut.importAndLoadMeasurements(from: file)
        TapToneAnalyzer.persistQueue.sync {}
        #expect(try Data(contentsOf: library) == damaged, "REGRESSION: a save wrote over the only copy")
    }
}
