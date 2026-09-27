//
//  WavDumpFolderTests.swift
//  GuitarTapTests
//
//  Pins the shared WAV-dump-folder logic: default folder, no-custom reachability, and the
//  acquire/release write helper. The macOS bookmark round-trip and the picker are checked by hand,
//  not here. Two-way with Python
//  test_wav_dump_folder.py (the web has no counterpart — a page can only download to Downloads).
//
// @parity test/wav-dump-folder

import Testing
import Foundation
@testable import GuitarTap

@Suite("WavDumpFolder", .serialized)
struct WavDumpFolderTests {

    /// Start from a clean slate — no custom folder — so shared assertions are deterministic.
    init() {
        #if os(macOS)
        WavDumpFolder.useDefaultFolder()
        #endif
    }

    @Test func defaultFolder_endsInGuitarTap() {
        #expect(WavDumpFolder.defaultFolder.lastPathComponent == "GuitarTap")
    }

    @Test func noCustomFolder_isReachable_andCurrentIsDefault() {
        #expect(WavDumpFolder.isReachable)
        #expect(WavDumpFolder.currentFolder.path == WavDumpFolder.defaultFolder.path)
    }

    #if os(macOS)
    @Test func hasCustomFolder_falseByDefault() {
        WavDumpFolder.useDefaultFolder()
        #expect(WavDumpFolder.hasCustomFolder == false)
    }
    #endif

    @Test func acquire_withNoCustomFolder_returnsTheDefault() {
        // No custom folder → the default (never nil); release is a no-op.
        let acquired = WavDumpFolder.acquireDumpFolder()
        #expect(acquired != nil)
        #expect(acquired?.folder.lastPathComponent == "GuitarTap")
        acquired?.release()
    }
}