//
//  ExportDirectoryTests.swift
//  GuitarTapTests
//
//  Pins the export Save panel's first-run default: it must resolve
//  the user's REAL ~/Documents/GuitarTap via getpwuid, not the sandbox container home that
//  homeDirectoryForCurrentUser / NSHomeDirectory return. macOS-sandbox-specific — Python/web are
//  not sandboxed and have no equivalent, so this is a justified platform-only test.
//
// @parity none — macOS App Sandbox path resolution; no cross-platform counterpart.

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