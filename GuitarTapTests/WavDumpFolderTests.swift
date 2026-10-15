//
//  WavDumpFolderTests.swift
//  GuitarTapTests
//
//  Pins the shared WAV-dump-folder logic: default folder, reachability, the acquire/release write
//  helper, and a custom folder that is in place, renamed, or deleted. The custom folder is stored in
//  the isolated test settings. The folder picker is checked by hand. Two-way with Python
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

    #if os(macOS)
    /// A fresh folder in the test's temp area, removed with `cleanUp`.
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(TestSandbox.name("com.guitartap.tests"))
            .appendingPathComponent("Captures-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp(_ urls: URL...) {
        WavDumpFolder.useDefaultFolder()
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    @Test func customFolder_isReachable_andIsCurrentAndAcquired() throws {
        let folder = try makeFolder()
        defer { cleanUp(folder) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        #expect(WavDumpFolder.hasCustomFolder)
        #expect(WavDumpFolder.isReachable)
        #expect(WavDumpFolder.currentFolder.path == folder.path)
        let acquired = WavDumpFolder.acquireDumpFolder()
        #expect(acquired?.folder.path == folder.path)
        acquired?.release()
    }

    @Test func renamedCustomFolder_isUnreachable_andAcquireSkips() throws {
        // The folder must stay where the user put it: a renamed folder is not followed.
        let folder = try makeFolder()
        let renamed = folder.deletingLastPathComponent().appendingPathComponent("Renamed-\(UUID().uuidString)")
        defer { cleanUp(folder, renamed) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        try FileManager.default.moveItem(at: folder, to: renamed)
        #expect(WavDumpFolder.hasCustomFolder)
        #expect(WavDumpFolder.isReachable == false)
        #expect(WavDumpFolder.acquireDumpFolder() == nil)
        #expect(WavDumpFolder.currentFolder.path == folder.path)
    }

    @Test func deletedCustomFolder_isUnreachable_andAcquireSkips() throws {
        let folder = try makeFolder()
        defer { cleanUp(folder) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        try FileManager.default.removeItem(at: folder)
        #expect(WavDumpFolder.isReachable == false)
        #expect(WavDumpFolder.acquireDumpFolder() == nil)
    }

    @Test func openFolder_withARenamedCustomFolder_opensTheDefault_notANewOne() throws {
        let folder = try makeFolder()
        let renamed = folder.deletingLastPathComponent().appendingPathComponent("Renamed-\(UUID().uuidString)")
        defer { cleanUp(folder, renamed) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        try FileManager.default.moveItem(at: folder, to: renamed)
        let (opened, release) = WavDumpFolder.folderToOpen()
        release()
        #expect(opened.path == WavDumpFolder.defaultFolder.path)
        #expect(FileManager.default.fileExists(atPath: folder.path) == false)
    }

    // Arming with Dump Capture Audio on checks the folder first: an unreachable folder is flagged
    // for the prompt and nothing is armed.

    @Test func requestStart_withAnUnreachableFolder_flagsIt_andDoesNotArm() throws {
        let folder = try makeFolder()
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump; cleanUp(folder) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        try FileManager.default.removeItem(at: folder)
        TapDisplaySettings.dumpCaptureAudio = true
        let sut = TapToneAnalyzer.forTesting()
        sut.requestStartTapSequence()
        #expect(sut.dumpFolderUnreachable)
        #expect(sut.isDetecting == false)
    }

    @Test func requestStart_withAReachableFolder_arms() throws {
        let folder = try makeFolder()
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump; cleanUp(folder) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        TapDisplaySettings.dumpCaptureAudio = true
        let sut = TapToneAnalyzer.forTesting()
        sut.requestStartTapSequence()
        #expect(sut.dumpFolderUnreachable == false)
        #expect(sut.isDetecting)
    }

    @Test func useDefaultFolder_forgetsTheCustomFolder() throws {
        let folder = try makeFolder()
        defer { cleanUp(folder) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        WavDumpFolder.useDefaultFolder()
        #expect(WavDumpFolder.hasCustomFolder == false)
        #expect(WavDumpFolder.currentFolder.path == WavDumpFolder.defaultFolder.path)
    }

    // A recording that can't be written when its measurement finishes is held, not dropped: the
    // user is asked, and choosing a folder saves it.

    /// The WAVs with `label` in `folder`.
    private func wavs(labelled label: String, in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("swift_\(label)_") && $0.hasSuffix(".wav") }
    }

    @Test func unwritableRecording_isHeld_andFlagged() throws {
        let folder = try makeFolder()
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump; cleanUp(folder) }
        #expect(WavDumpFolder.setCustomFolder(folder))
        try FileManager.default.removeItem(at: folder)
        TapDisplaySettings.dumpCaptureAudio = true
        let sut = TapToneAnalyzer.forTesting()
        sut.dumpCaptureWAV(samples: [0.1, -0.1, 0.2], sampleRate: 48000, label: "held")
        #expect(sut.heldCaptureRecordings.count == 1)
        #expect(sut.captureRecordingHeld)
    }

    @Test func heldRecording_isSavedToTheFolderTheUserChooses() throws {
        let gone = try makeFolder()
        let chosen = try makeFolder()
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump; cleanUp(gone, chosen) }
        #expect(WavDumpFolder.setCustomFolder(gone))
        try FileManager.default.removeItem(at: gone)
        TapDisplaySettings.dumpCaptureAudio = true
        let sut = TapToneAnalyzer.forTesting()
        sut.dumpCaptureWAV(samples: [0.1, -0.1, 0.2], sampleRate: 48000, label: "held")
        #expect(WavDumpFolder.setCustomFolder(chosen))
        sut.saveHeldCaptureRecordings()
        #expect(sut.heldCaptureRecordings.isEmpty)
        #expect(wavs(labelled: "held", in: chosen).count == 1)
        #expect(sut.captureAudioSaved?.hasPrefix("swift_held_") == true)
    }

    @Test func heldRecording_isDiscardedWhenTheUserLetsItGo() throws {
        let gone = try makeFolder()
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump; cleanUp(gone) }
        #expect(WavDumpFolder.setCustomFolder(gone))
        try FileManager.default.removeItem(at: gone)
        TapDisplaySettings.dumpCaptureAudio = true
        let sut = TapToneAnalyzer.forTesting()
        sut.dumpCaptureWAV(samples: [0.1, -0.1, 0.2], sampleRate: 48000, label: "held")
        sut.discardHeldCaptureRecordings()
        #expect(sut.heldCaptureRecordings.isEmpty)
        #expect(wavs(labelled: "held", in: WavDumpFolder.defaultFolder).isEmpty)
    }
    #endif

    // Whether the recording is saved is read from the saving setting when a sequence starts, and
    // again when the setting changes before the first tap (the shared cases in
    // session-pre-roll.json). A loaded measurement or comparison ends the sequence and its recording.

    private let chunk = [Float](repeating: 0.1, count: 1024)

    @Test func savingOff_recordsNothing() {
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        TapDisplaySettings.dumpCaptureAudio = false
        let sut = TapToneAnalyzer.forTesting()
        sut.startTapSequence()
        sut.gatedCaptureActive = true
        for _ in 0..<10 { sut.maintainSessionRecording(appending: chunk) }
        #expect(!sut.isSessionRecording)
        #expect(sut.sessionRecordingBuffer.isEmpty)
    }

    @Test func savingTurnedOnAfterTheFirstTap_takesEffectFromTheNextSequence() {
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        TapDisplaySettings.dumpCaptureAudio = false
        let sut = TapToneAnalyzer.forTesting()
        sut.startTapSequence()
        sut.gatedCaptureActive = true
        sut.maintainSessionRecording(appending: chunk)
        TapDisplaySettings.dumpCaptureAudio = true
        sut.applyDumpCaptureAudioSetting()
        // A pause and resume does not start it either.
        sut.pauseTapDetection()
        sut.resumeTapDetection()
        sut.maintainSessionRecording(appending: chunk)
        #expect(!sut.isSessionRecording)
        #expect(sut.sessionRecordingBuffer.isEmpty)
        let folder = WavDumpFolder.defaultFolder
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        sut.finishSessionRecording(label: "Guitar_1tap")
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        #expect(after.subtracting(before).filter { $0.hasPrefix("swift_session_Guitar_1tap_") }.isEmpty)
        // The next sequence records.
        sut.startTapSequence()
        #expect(sut.isSessionRecordingEnabled)
        #expect(sut.isSessionRecording)
    }

    @Test func loadingAMeasurement_endsTheRecording() {
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        TapDisplaySettings.dumpCaptureAudio = true
        let sut = TapToneAnalyzer.forTesting()
        sut.startTapSequence()
        sut.gatedCaptureActive = true
        for _ in 0..<10 { sut.maintainSessionRecording(appending: chunk) }
        #expect(!sut.sessionRecordingBuffer.isEmpty)
        sut.loadMeasurement(TapToneMeasurement(peaks: []))
        #expect(!sut.isSessionRecording)
        #expect(sut.sessionRecordingBuffer.isEmpty)
        // Audio after the load is not kept.
        sut.maintainSessionRecording(appending: chunk)
        #expect(sut.sessionRecordingBuffer.isEmpty)
    }

    // A save is shown: the analyzer names the file it wrote, until dismissed or a new sequence starts.

    @Test func savedNotice_namesTheFile_untilDismissedOrANewSequence() {
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        TapDisplaySettings.dumpCaptureAudio = true
        let folder = WavDumpFolder.defaultFolder
        defer {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasPrefix("swift_notice_") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        let sut = TapToneAnalyzer.forTesting()
        sut.dumpCaptureWAV(samples: [0.1, -0.1, 0.2], sampleRate: 48000, label: "notice")
        #expect(sut.captureAudioSaved?.hasPrefix("swift_notice_") == true)
        sut.dismissCaptureAudioSaved()
        #expect(sut.captureAudioSaved == nil)

        sut.dumpCaptureWAV(samples: [0.1, -0.1, 0.2], sampleRate: 48000, label: "notice")
        #expect(sut.captureAudioSaved != nil)
        sut.startTapSequence()
        #expect(sut.captureAudioSaved == nil)
    }

    @Test func savedNotice_notShownWhenSavingIsOff() {
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        TapDisplaySettings.dumpCaptureAudio = false
        let sut = TapToneAnalyzer.forTesting()
        sut.dumpCaptureWAV(samples: [0.1, -0.1, 0.2], sampleRate: 48000, label: "notice")
        #expect(sut.captureAudioSaved == nil)
    }
}
