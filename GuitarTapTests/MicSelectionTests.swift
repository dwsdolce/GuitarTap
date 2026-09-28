//
//  MicSelectionTests.swift
//  GuitarTapTests
//
//  Tests for which input device the engine uses and what it saves: the launch rule
//  inputDeviceToUse (MS1–MS5), the engine driven through applyInputDeviceList, a Settings
//  selection and setInputDevice (MS6–MS11), a measurement load switching to its recorded
//  microphone (MS14–MS17), choosing a calibration for the selected device (MS18–MS20), and the
//  thresholds a load restores, saved as a setting (MS21–MS22).
//  MS12–MS13 are Python only.
//
//  The rules: at launch, the saved device when it is present, otherwise the system default
//  input, otherwise the first device; a device connected while running is selected; the device
//  in use disappearing selects the system default, otherwise the first device. Every selection
//  is saved, so what Settings shows is what the next launch uses.
//
//  The saved device and the calibration store live in TapDisplaySettings.defaults, an isolated
//  suite under test.
//
//  Test plan coverage: MS1–MS11, MS14–MS22 — the same list, ids and devices as Python
//  test_mic_selection.py and web test/mic-selection.test.ts.
//
// @parity test/mic-selection

#if os(macOS)
import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private func device(_ name: String, _ id: UInt32) -> AVAudioDevice {
    AVAudioDevice(name: name, uid: "\(name)-uid", sampleRate: 48000, deviceID: id)
}

private let builtIn = device("MacBook Pro Microphone", 1)
private let blackHole = device("BlackHole 2ch", 2)
private let umik = device("UMIK-1", 3)
private let usb2 = device("USB Mic 2", 4)

/// A fresh engine with `saved` as the saved choice (nil: nothing saved).
@MainActor
private func makeSUT(saved: AVAudioDevice?) -> RealtimeFFTAnalyzer {
    TapDisplaySettings.selectedInputDeviceUID = saved?.uid
    return RealtimeFFTAnalyzer.forTesting()
}

@Suite("MicSelection", .serialized)
@MainActor
struct MicSelectionTests {

    // MARK: - The rule

    // MS1: The saved device wins when it is present — over the system default, and over any
    //      other device (the built-in mic is kept although a USB mic and BlackHole are listed).
    @Test func MS1_savedPresent_wins() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [blackHole, builtIn, umik], savedUID: builtIn.uid, systemDefaultUID: umik.uid)
        #expect(chosen == builtIn)
    }

    // MS2: The saved device is not connected — the system default.
    @Test func MS2_savedAbsent_usesSystemDefault() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [blackHole, builtIn], savedUID: umik.uid, systemDefaultUID: builtIn.uid)
        #expect(chosen == builtIn)
    }

    // MS3: Nothing saved — the system default, not a device listed ahead of it (BlackHole).
    @Test func MS3_nothingSaved_usesSystemDefault() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [blackHole, builtIn], savedUID: nil, systemDefaultUID: builtIn.uid)
        #expect(chosen == builtIn)
    }

    // MS4: No usable system default — the first device.
    @Test func MS4_noDefault_usesFirstDevice() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [umik, builtIn], savedUID: nil, systemDefaultUID: nil)
        #expect(chosen == umik)
    }

    // MS5: No devices — nothing.
    @Test func MS5_noDevices_selectsNothing() {
        #expect(RealtimeFFTAnalyzer.inputDeviceToUse(in: [], savedUID: builtIn.uid,
                                                     systemDefaultUID: builtIn.uid) == nil)
    }

    // MARK: - The engine: what is selected, and what is saved

    // MS6: The launch selection is saved: nothing saved, the default is selected and saved.
    @Test func MS6_launchSelection_isSaved() {
        let sut = makeSUT(saved: nil)
        sut.applyInputDeviceList([blackHole, builtIn], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == builtIn)
        #expect(TapDisplaySettings.selectedInputDeviceUID == builtIn.uid)
    }

    // MS7: A device selected in Settings is selected and saved.
    @Test func MS7_settingsSelection_isSaved() {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        sut.selectedInputDevice = umik
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MS8: A device plugged in while running is selected and saved.
    @Test func MS8_pluggedIn_isSelectedAndSaved() {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn], systemDefaultUID: builtIn.uid)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == umik)
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MS9: The device in use unplugged (or dropping out) — the system default, selected and
    //      saved, so the next launch is on what Settings shows.
    @Test func MS9_inUseUnplugged_fallsBackAndSaves() {
        let sut = makeSUT(saved: umik)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == umik)
        sut.applyInputDeviceList([builtIn], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == builtIn)
        #expect(TapDisplaySettings.selectedInputDeviceUID == builtIn.uid)
    }

    // MS10: The device in use unplugged falls to the system default, not to another connected
    //       USB mic.
    @Test func MS10_inUseUnplugged_fallsToTheDefault_notAnotherUSBMic() {
        let sut = makeSUT(saved: usb2)
        sut.applyInputDeviceList([builtIn, umik, usb2], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == usb2)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == builtIn)
        #expect(TapDisplaySettings.selectedInputDeviceUID == builtIn.uid)
    }

    // MS11: The switch a measurement load makes to its recorded microphone is saved.
    @Test func MS11_loadSwitch_isSaved() throws {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        try sut.setInputDevice(umik)
        #expect(sut.selectedInputDevice == umik)
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MARK: - Loading a measurement recorded with another connected microphone

    /// An analyzer on the built-in mic (saved) with a calibration, the USB mic connected, and a
    /// measurement recorded with `mic` and `calibrationName`, loaded.
    private func load(recordedWith mic: AVAudioDevice, calibrationName: String? = nil) -> TapToneAnalyzer {
        TapDisplaySettings.selectedInputDeviceUID = builtIn.uid
        let sut = TapToneAnalyzer.forTesting()
        sut.fftAnalyzer.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        sut.fftAnalyzer.setCalibrationWithoutSavingDeviceMapping(
            MicrophoneCalibration(name: "Built-in room", correctionPoints: []))
        sut.loadMeasurement(TapToneMeasurement(peaks: [], measurementName: "Loaded",
                                               microphoneName: mic.name, microphoneUID: mic.uid,
                                               calibrationName: calibrationName))
        return sut
    }

    private func loadRecordedWithUSBMic() -> TapToneAnalyzer { load(recordedWith: umik) }

    // MS14: The load has switched to the recorded microphone, and saved it, by the time it returns.
    @Test func MS14_loadSwitch_isInPlaceWhenTheLoadReturns() {
        let sut = loadRecordedWithUSBMic()
        #expect(sut.fftAnalyzer.selectedInputDevice == umik)
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MS15: The calibration check compares the recorded microphone's calibration (none) — not
    //       that of the microphone switched away from ("Built-in room") — so no warning.
    @Test func MS15_loadCheck_readsTheRecordedMicrophone() {
        let sut = loadRecordedWithUSBMic()
        #expect(sut.fftAnalyzer.activeCalibration == nil)
        #expect(sut.microphoneWarning == nil, "warned: \(sut.microphoneWarning ?? "")")
    }

    // MS16: No connected microphone matches — the not-found warning; the input is unchanged.
    @Test func MS16_noMatch_warnsAndKeepsTheInput() {
        let sut = load(recordedWith: device("Absent Mic", 9))
        #expect(sut.fftAnalyzer.selectedInputDevice == builtIn)
        #expect(sut.microphoneWarning?.hasPrefix(
            "Recorded with 'Absent Mic'. No connected microphone matches that name") == true)
    }

    // MS17: The recorded microphone is the current one but its calibration differs — the warning.
    @Test func MS17_sameMicrophone_differentCalibration_warns() {
        let sut = load(recordedWith: builtIn, calibrationName: "Other")
        #expect(sut.microphoneWarning ==
            "This measurement was recorded with a different calibration. A newly captured tap may not match the saved result.")
    }

    // MARK: - Choosing a calibration

    /// An engine on the built-in mic with the USB mic connected, an empty calibration store, and
    /// `room` saved in it.
    private func engineWithStoredCalibration() -> (RealtimeFFTAnalyzer, MicrophoneCalibration) {
        let storage = CalibrationStorage.shared
        storage.loadAll().forEach { storage.delete($0) }
        storage.activeCalibrationID = nil
        [builtIn, umik].forEach { storage.setCalibration(nil, forDeviceUID: $0.uid) }
        let room = MicrophoneCalibration(name: "Room", correctionPoints: [])
        storage.save(room)
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        return (sut, room)
    }

    // MS18: A calibration chosen for the selected device is saved for it (and as the last
    //       chosen); switching to another device and back restores it.
    @Test func MS18_chosenCalibration_isSavedForTheDevice() {
        let (sut, room) = engineWithStoredCalibration()
        sut.activeCalibration = room
        #expect(CalibrationStorage.shared.calibration(forDeviceUID: builtIn.uid)?.id == room.id)
        #expect(CalibrationStorage.shared.activeCalibrationID == room.id)
        sut.selectedInputDevice = umik
        #expect(sut.activeCalibration == nil)
        sut.selectedInputDevice = builtIn
        #expect(sut.activeCalibration?.id == room.id)
    }

    // MS19: Choosing no calibration removes the device's: switching away and back gives none.
    @Test func MS19_choosingNone_removesTheDevicesCalibration() {
        let (sut, room) = engineWithStoredCalibration()
        sut.activeCalibration = room
        sut.activeCalibration = nil
        #expect(CalibrationStorage.shared.calibration(forDeviceUID: builtIn.uid) == nil)
        #expect(CalibrationStorage.shared.activeCalibrationID == nil)
        sut.selectedInputDevice = umik
        sut.selectedInputDevice = builtIn
        #expect(sut.activeCalibration == nil)
    }

    // MARK: - A load restores settings as the user setting them would

    // MS21: A load saves the thresholds it restores, so they are the settings at the next launch.
    @Test func MS21_load_savesTheThresholdsItRestores() {
        TapDisplaySettings.tapDetectionThreshold = -40
        TapDisplaySettings.peakMinThreshold = -60
        let sut = TapToneAnalyzer.forTesting()
        sut.loadMeasurement(TapToneMeasurement(peaks: [], measurementName: "Loaded",
                                               tapDetectionThreshold: -30, peakMinThreshold: -50))
        #expect(TapDisplaySettings.tapDetectionThreshold == -30)
        #expect(TapDisplaySettings.peakMinThreshold == -50)
    }

    // MS22: Setting a threshold on the analyzer saves it.
    @Test func MS22_settingAThreshold_savesIt() {
        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = -35
        sut.peakMinThreshold = -45
        #expect(TapDisplaySettings.tapDetectionThreshold == -35)
        #expect(TapDisplaySettings.peakMinThreshold == -45)
    }

    // MS20: A file playback's calibration (temporary) is applied but saves nothing.
    @Test func MS20_temporaryCalibration_savesNothing() {
        let (sut, room) = engineWithStoredCalibration()
        sut.setTemporaryCalibration(room)
        #expect(sut.activeCalibration?.id == room.id)
        #expect(CalibrationStorage.shared.calibration(forDeviceUID: builtIn.uid) == nil)
        #expect(CalibrationStorage.shared.activeCalibrationID == nil)
    }
}
#endif
