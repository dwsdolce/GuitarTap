//
//  ExportDirectoryTests.swift
//  GuitarTapTests
//
//  Pins the export Save panel's first-run default: the user's ~/Documents/GuitarTap — the REAL
//  home's, via getpwuid, not the sandbox container home that homeDirectoryForCurrentUser /
//  NSHomeDirectory return (the second test is the sandbox's alone). Python's default is the same
//  folder (tests/test_export_directory.py); the web has no folder of its own (a download).
//
// @parity test/export-directory

#if os(macOS)
import Testing
import Foundation
@testable import GuitarTap

@Suite("ExportDirectory")
struct ExportDirectoryTests {

    private var realHome: String { String(cString: getpwuid(getuid())!.pointee.pw_dir) }

    @Test func defaultSaveDirectory_isTheRealDocumentsGuitarTap() {
        let expected = URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent("Documents/GuitarTap")
        #expect(MeasurementFileExporter.defaultSaveDirectory.path == expected.path)
    }

    @Test func defaultSaveDirectory_isNotTheSandboxContainer() {
        // Under App Sandbox homeDirectoryForCurrentUser returns the container; the default must not.
        let container = FileManager.default.homeDirectoryForCurrentUser.path
        let def = MeasurementFileExporter.defaultSaveDirectory.path
        // The container path lives under …/Library/Containers/… ; the real default must not.
        if container.contains("/Library/Containers/") {
            #expect(!def.contains("/Library/Containers/"),
                    "Save panel default must be the real ~/Documents/GuitarTap, not the container")
        }
        #expect(def.hasSuffix("/Documents/GuitarTap"))
    }
}
#endif