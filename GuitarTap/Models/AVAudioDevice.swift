//
//  AVAudioDevice.swift
//  GuitarTap
//
//  Created by David Smith on 2/12/26.
//

/// # AVAudioDevice
///
/// A lightweight, platform-agnostic wrapper for a physical or virtual audio input device.
///
/// On **macOS**, the system exposes audio devices via CoreAudio's `AudioDeviceID` and a
/// string UID.  On **iOS**, the equivalent is an `AVAudioSessionPortDescription` from the
/// AVAudioSession route.  `AVAudioDevice` provides a unified type that hides this platform
/// difference, allowing `RealtimeFFTAnalyzer` and `TapToneAnalibration` to work with a single
/// device type regardless of platform.
///
/// ## Identity and Equality
///
/// Equality and hashing are based on ``uid``, not the ephemeral ``id`` UUID.  This means two
/// instances that describe the same physical device will compare equal even if they were
/// constructed at different times (e.g. after a device reconnect).  The ``uid`` is also used
/// as the key in ``CalibrationStorage``'s device-to-calibration mapping.
import Foundation
import AVFoundation

#if os(macOS)
import CoreAudio
#endif

/// A platform-independent representation of an audio input device.
///
/// Equality is determined by ``uid`` so that the same physical device is considered equal
/// across multiple discovery passes or application launches.
///
/// - SeeAlso: ``RealtimeFFTAnalyzer`` which populates and manages the list of available devices.
/// - SeeAlso: ``CalibrationStorage`` which maps device UIDs to calibration profiles.
struct AVAudioDevice: Identifiable, Hashable {

    /// A transient UUID used by SwiftUI list identifiers.
    ///
    /// - Note: This value changes every time a new `AVAudioDevice` is constructed.
    ///   Use ``uid`` for persistent device identity.
    let id = UUID()

    /// Human-readable display name of the device (e.g. `"MacBook Pro Microphone"`).
    let name: String

    /// Platform-assigned unique identifier string for this device.
    ///
    /// On macOS this comes from `kAudioDevicePropertyDeviceUID`; on iOS from
    /// `AVAudioSessionPortDescription.uid`.  Used as the key for device-specific calibration
    /// mappings and for persisting the user's selected input device across launches.
    let uid: String

    /// The nominal hardware sample rate reported by the device, in Hz (e.g. `48000.0`).
    ///
    /// This is used to inform the audio engine's session configuration and FFT bin spacing.
    let sampleRate: Double

#if os(macOS)

    /// The CoreAudio `AudioDeviceID` assigned by the system.
    ///
    /// Required on macOS to set the preferred input device on `AVAudioEngine`'s input node
    /// and to register hardware property listeners for route-change notifications.
    ///
    /// - Note: Available on **macOS only**.
    let deviceID: AudioDeviceID

    /// Creates an `AVAudioDevice` from macOS CoreAudio metadata.
    ///
    /// - Parameters:
    ///   - name: Human-readable device name.
    ///   - uid: CoreAudio UID string from `kAudioDevicePropertyDeviceUID`.
    ///   - sampleRate: Nominal hardware sample rate in Hz.
    ///   - deviceID: The CoreAudio `AudioDeviceID` for this device.
    init(name: String, uid: String, sampleRate: Double, deviceID: AudioDeviceID) {
        self.name = name
        self.uid = uid
        self.sampleRate = sampleRate
        self.deviceID = deviceID
    }

#else

    /// The AVAudioSession port description backing this device.
    ///
    /// `nil` for the default system input when no specific port is available.
    ///
    /// - Note: Available on **iOS only**.
    let port: AVAudioSessionPortDescription?

    /// Creates an `AVAudioDevice` from an iOS AVAudioSession port description.
    ///
    /// - Parameters:
    ///   - name: Human-readable device name.
    ///   - uid: Port UID from `AVAudioSessionPortDescription.uid`.
    ///   - sampleRate: Nominal hardware sample rate in Hz.
    ///   - port: The underlying `AVAudioSessionPortDescription`, or `nil` for the default input.
    init(name: String, uid: String, sampleRate: Double, port: AVAudioSessionPortDescription?) {
        self.name = name
        self.uid = uid
        self.sampleRate = sampleRate
        self.port = port
    }

#endif

    // MARK: - Hashable / Equatable

    /// Hashes the device using only ``uid`` so that the same physical device produces the
    /// same hash value across separate `AVAudioDevice` instances.
    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }

    /// Two devices are equal when their ``uid`` values match, regardless of the transient ``id``.
    static func == (lhs: AVAudioDevice, rhs: AVAudioDevice) -> Bool {
        lhs.uid == rhs.uid
    }
}
