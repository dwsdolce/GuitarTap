//
//  RealtimeFFTAnalyzer+DeviceManagement.swift
//  GuitarTap
//

import AVFoundation

#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

// MARK: - Audio Device Management

extension RealtimeFFTAnalyzer {

    /// Refreshes `availableInputDevices` from the platform audio subsystem.
    ///
    /// Dispatches to the platform-specific implementation:
    /// - macOS: `loadAvailableInputDevicesMacOS()` via CoreAudio
    /// - iOS: `loadAvailableInputDevicesIOS()` via `AVAudioSession`
    ///
    /// Called at init, after `start()` (iOS), and on device connect/disconnect events.
    func loadAvailableInputDevices() {
        #if os(macOS)
        loadAvailableInputDevicesMacOS()
        #else
        loadAvailableInputDevicesIOS()
        #endif
    }
    
    #if os(macOS)
    /// Enumerates CoreAudio input devices and updates `availableInputDevices`.
    ///
    /// Queries `kAudioHardwarePropertyDevices`, filters for devices with at least
    /// one input channel (`kAudioDevicePropertyStreamConfiguration`), and reads each
    /// device's display name, UID, and nominal sample rate.
    ///
    /// ## Auto-selection Policy (initial load)
    /// 1. Previously persisted device UID (`UserDefaults` key `selectedInputDeviceUID`)
    /// 2. Built-in microphone (UID contains `"BuiltInMicrophone"`)
    /// 3. System default input device (`kAudioHardwarePropertyDefaultInputDevice`)
    /// 4. First device in the enumerated list
    ///
    /// On subsequent calls (device connect/disconnect): newly appeared real devices
    /// are auto-selected; aggregate devices matching `"CADefaultDeviceAggregate"` are
    /// ignored; if the current device disappeared, falls back to built-in or first.
    func loadAvailableInputDevicesMacOS() {
        var devices: [AVAudioDevice] = []
        
        // Use Core Audio to enumerate audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("⚠️ Could not get audio device count")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("⚠️ Could not get audio devices")
            return
        }
        
        // Filter for input devices and get their info
        for deviceID in deviceIDs {
            // Check if device has input channels
            var streamPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            status = AudioObjectGetPropertyDataSize(
                deviceID,
                &streamPropertyAddress,
                0,
                nil,
                &dataSize
            )
            
            guard status == noErr else { continue }
            
            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferList.deallocate() }
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &streamPropertyAddress,
                0,
                nil,
                &dataSize,
                bufferList
            )
            
            guard status == noErr else { continue }
            
            // Use withUnsafePointer to safely access the mBuffers tuple
            let channelCount = withUnsafePointer(to: &bufferList.pointee.mBuffers) { buffersPtr in
                let bufferCount = Int(bufferList.pointee.mNumberBuffers)
                var count = 0
                for i in 0..<bufferCount {
                    let bufferPtr = buffersPtr.advanced(by: i)
                    count += Int(bufferPtr.pointee.mNumberChannels)
                }
                return count
            }
            
            // Skip devices with no input channels
            guard channelCount > 0 else { continue }
            
            // Get device name
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            // Use Unmanaged for CFString to avoid object reference issues
            var cfStringRef: Unmanaged<CFString>?
            dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &namePropertyAddress,
                0,
                nil,
                &dataSize,
                &cfStringRef
            )
            
            let name: String
            if status == noErr, let cfString = cfStringRef?.takeUnretainedValue() {
                name = cfString as String
            } else {
                name = "Unknown Device"
            }
            
            // Get sample rate
            var sampleRateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var sampleRate: Float64 = 48000.0
            dataSize = UInt32(MemoryLayout<Float64>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &sampleRateAddress,
                0,
                nil,
                &dataSize,
                &sampleRate
            )
            
            // Get device UID
            var uidPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            // Use Unmanaged for CFString to avoid object reference issues
            var cfUIDRef: Unmanaged<CFString>?
            dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &uidPropertyAddress,
                0,
                nil,
                &dataSize,
                &cfUIDRef
            )
            
            let uid: String
            if status == noErr, let cfUID = cfUIDRef?.takeUnretainedValue() {
                uid = cfUID as String
            } else {
                uid = "\(deviceID)"
            }
            
            let device = AVAudioDevice(
                name: name,
                uid: uid,
                sampleRate: sampleRate,
                deviceID: deviceID
            )
            
            devices.append(device)
            print("🎤 Found input device: \(name) @ \(sampleRate) Hz (UID: \(uid))")
        }
        
        DispatchQueue.main.async {
            let previousDevices = self.availableInputDevices
            self.availableInputDevices = devices

            if previousDevices.isEmpty {
                // ── Initial load: priority-based auto-selection ──────────────────
                guard !devices.isEmpty else { return }

                // Priority 0: Restore previously selected device (persisted across launches)
                if let savedUID = UserDefaults.standard.string(forKey: "selectedInputDeviceUID"),
                   let savedDevice = devices.first(where: { $0.uid == savedUID }) {
                    self.selectedInputDevice = savedDevice
                    print("🎤 Restored previously selected mic: \(savedDevice.name)")
                } else
                // Priority 1: Built-in microphone
                if let builtInMic = devices.first(where: { $0.uid.contains("BuiltInMicrophone") }) {
                    self.selectedInputDevice = builtInMic
                    print("🎤 Auto-selected built-in mic: \(builtInMic.name)")
                } else {
                    // Priority 2: System default input device
                    var defaultDeviceID: AudioDeviceID = 0
                    var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
                    var defaultDeviceAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    let status = AudioObjectGetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultDeviceAddress,
                        0,
                        nil,
                        &defaultDeviceIDSize,
                        &defaultDeviceID
                    )
                    if status == noErr, defaultDeviceID != 0,
                       let defaultDevice = devices.first(where: { $0.deviceID == defaultDeviceID }) {
                        self.selectedInputDevice = defaultDevice
                        print("🎤 Auto-selected system default: \(defaultDevice.name) (ID: \(defaultDeviceID))")
                    } else {
                        // Priority 3: First available device
                        self.selectedInputDevice = devices.first
                        print("🎤 Auto-selected first device: \(devices.first!.name)")
                    }
                }
            } else {
                // ── Device list changed (connect or disconnect) ──────────────────
                let newlyConnected = devices.filter { newDev in
                    !previousDevices.contains(where: { $0.uid == newDev.uid })
                }

                // Ignore transient aggregate devices that macOS creates internally during
                // audio session setup (e.g. after a permission revocation restart).
                // These have UIDs matching "CADefaultDeviceAggregate" and are not real
                // user-facing microphones.
                let realNewDevices = newlyConnected.filter { !$0.uid.contains("CADefaultDeviceAggregate") }

                if let firstNew = realNewDevices.first {
                    // New real device plugged in — switch to it automatically
                    self.selectedInputDevice = firstNew
                    print("🎤 New device connected, auto-selected: \(firstNew.name)")
                } else if let current = self.selectedInputDevice,
                          !devices.contains(where: { $0.uid == current.uid }) {
                    // Currently selected device was unplugged — fall back
                    if let builtIn = devices.first(where: { $0.uid.contains("BuiltInMicrophone") }) {
                        self.selectedInputDevice = builtIn
                        print("🎤 '\(current.name)' disconnected, switched to built-in: \(builtIn.name)")
                    } else {
                        self.selectedInputDevice = devices.first
                        print("🎤 '\(current.name)' disconnected, switched to: \(devices.first?.name ?? "none")")
                    }
                }
                // If selected device is still present, no change needed
            }
        }
        
        print("🎤 Found \(devices.count) audio input device(s) total")
    }

    /// Registers a CoreAudio `kAudioHardwarePropertyDevices` listener on the
    /// system object so `availableInputDevices` refreshes whenever a device
    /// connects or disconnects.
    ///
    /// The retained listener block is stored in `hardwareListenerBlock` so it
    /// can be removed cleanly in ``unregisterMacOSHardwareListener()``.
    func registerMacOSHardwareListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // CoreAudio may call this on any thread; loadAvailableInputDevicesMacOS
            // dispatches to main internally for all @Published updates.
            self?.loadAvailableInputDevices()
        }
        hardwareListenerBlock = block
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )
        if status != noErr {
            print("⚠️ Failed to register CoreAudio device change listener: \(status)")
        } else {
            print("✅ Registered CoreAudio device change listener")
        }
    }

    /// Removes the CoreAudio hardware-change listener from the system object and
    /// also calls ``unregisterSampleRateListener()`` to clean up the per-device
    /// listener. Safe to call multiple times.
    func unregisterMacOSHardwareListener() {
        guard let block = hardwareListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )
        hardwareListenerBlock = nil
        unregisterSampleRateListener()
    }

    /// Registers a CoreAudio `kAudioDevicePropertyNominalSampleRate` listener on
    /// the given device. When the sample rate changes while the engine is running
    /// (e.g. because the user adjusted it in Audio MIDI Setup), the engine is
    /// stopped and restarted so `actualSampleRate` and the frequency bin axis
    /// update to reflect the new rate.
    ///
    /// Replaces any previously registered sample-rate listener before adding the
    /// new one. The new listener is stored in `sampleRateListenerBlock`.
    ///
    /// - Parameter deviceID: The `AudioDeviceID` to watch for sample-rate changes.
    func registerSampleRateListener(for deviceID: AudioDeviceID) {
        // Remove any previous registration before adding a new one
        unregisterSampleRateListener()
        guard deviceID != 0 else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            print("🔄 Sample rate changed on device \(deviceID) — restarting engine if running")
            DispatchQueue.main.async {
                guard self.isRunning else { return }
                self.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    do {
                        try self.start()
                        self.routeChangeRestartCount += 1
                        print("✅ Engine restarted after sample rate change (restart #\(self.routeChangeRestartCount))")
                    } catch {
                        print("❌ Failed to restart engine after sample rate change: \(error)")
                    }
                }
            }
        }
        sampleRateListenerBlock = block
        sampleRateListenerDeviceID = deviceID
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
        if status == noErr {
            print("✅ Registered sample rate listener for device \(deviceID)")
        } else {
            print("⚠️ Failed to register sample rate listener for device \(deviceID): \(status)")
        }
    }

    /// Removes the `kAudioDevicePropertyNominalSampleRate` listener from the
    /// device it was registered against and clears `sampleRateListenerBlock`
    /// and `sampleRateListenerDeviceID`. No-op if no listener is registered.
    func unregisterSampleRateListener() {
        guard let block = sampleRateListenerBlock, sampleRateListenerDeviceID != 0 else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(sampleRateListenerDeviceID, &address, nil, block)
        sampleRateListenerBlock = nil
        sampleRateListenerDeviceID = 0
    }
    #endif
    
    #if os(iOS)
    /// Enumerates `AVAudioSession.availableInputs` and updates `availableInputDevices`.
    ///
    /// Configures the audio session to `.playAndRecord` / `.measurement` before
    /// querying, because iOS will not expose external USB audio devices unless a
    /// recording category is active. This configuration step is **skipped** if the
    /// engine is already running to avoid invalidating the active audio tap.
    ///
    /// Selects `session.currentRoute.inputs.first` if it matches an available device;
    /// otherwise selects the first device in the list.
    func loadAvailableInputDevicesIOS() {
        let session = AVAudioSession.sharedInstance()
        var devices: [AVAudioDevice] = []
        
        // CRITICAL: Only configure audio session if not already running
        // If the engine is running, changing the category can invalidate the audio tap
        // and cause the app to stop receiving audio data.
        if !audioEngine.isRunning {
            // Configure audio session BEFORE querying available inputs
            // Without setting the category to .record or .playAndRecord, iOS will NOT
            // expose external USB audio devices (like UMIK-1) in availableInputs.
            do {
                // Use .playAndRecord to maximize device discovery
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP])
                try session.setActive(true, options: [])
                print("🎙️ iOS audio session configured for device enumeration")
            } catch {
                print("⚠️ Failed to configure audio session for device enumeration: \(error)")
                // Continue anyway - we may still get some devices
            }
        } else {
            print("🎙️ Skipping audio session reconfiguration - engine is running")
        }
        
        // Get available inputs from AVAudioSession
        guard let availableInputs = session.availableInputs else {
            print("⚠️ No audio inputs available")
            
            // Add current route as fallback
            if let currentInput = session.currentRoute.inputs.first {
                let device = AVAudioDevice(
                    name: currentInput.portName,
                    uid: currentInput.uid,
                    sampleRate: session.sampleRate,
                    port: currentInput
                )
                devices.append(device)
            }
            
            DispatchQueue.main.async {
                self.availableInputDevices = devices
                if let first = devices.first {
                    self.selectedInputDevice = first
                }
            }
            return
        }
        
        // Convert AVAudioSessionPortDescription to AVAudioDevice
        // Filter out invalid or unusable ports
        for port in availableInputs {
            // Skip ports with empty or invalid names
            guard !port.portName.isEmpty else {
                print("⚠️ Skipping port with empty name (UID: \(port.uid))")
                continue
            }
            
            // Create device - avoid directly printing portType.rawValue as it may contain
            // internal values that trigger warnings
            let device = AVAudioDevice(
                name: port.portName,
                uid: port.uid,
                sampleRate: session.sampleRate,
                port: port
            )
            devices.append(device)
            
            // Safe logging - only print known port types
            let portTypeDescription = getPortTypeDescription(port.portType)
            print("🎤 Found input device: \(port.portName) [\(portTypeDescription)] @ \(session.sampleRate) Hz")
        }
        
        DispatchQueue.main.async {
            self.availableInputDevices = devices
            
            // Try to select the current input, or first device
            if let currentInput = session.currentRoute.inputs.first,
               let matchingDevice = devices.first(where: { $0.uid == currentInput.uid }) {
                self.selectedInputDevice = matchingDevice
            } else if let first = devices.first {
                self.selectedInputDevice = first
            }
        }
        
        print("🎤 Found \(devices.count) audio input device(s) total")
    }
    
    /// Maps an `AVAudioSession.Port` to a user-readable string without
    /// accessing the raw value of unknown cases, which can trigger internal
    /// framework warnings on some OS versions.
    ///
    /// - Parameter portType: The `AVAudioSession.Port` to describe.
    /// - Returns: A localisation-friendly string such as `"USB Audio"` or
    ///   `"Built-in Microphone"`. Returns `"Audio Input"` for unrecognised
    ///   port types.
    func getPortTypeDescription(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .headsetMic:
            return "Headset Microphone"
        case .lineIn:
            return "Line In"
        case .airPlay:
            return "AirPlay"
        case .bluetoothA2DP:
            return "Bluetooth A2DP"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .bluetoothHFP:
            return "Bluetooth Hands-Free"
        case .usbAudio:
            return "USB Audio"
        case .carAudio:
            return "CarPlay"
        case .virtual:
            return "Virtual"
        default:
            // Don't print the raw value for unknown types as it may trigger warnings
            return "Audio Input"
        }
    }
    
    /// Handles `AVAudioSession.routeChangeNotification` on iOS.
    ///
    /// Reacts to three reason codes:
    /// - `.newDeviceAvailable` — refreshes device list and restarts engine if running.
    /// - `.oldDeviceUnavailable` — refreshes device list and restarts engine if running.
    /// - `.categoryChange` — refreshes device list only (engine restart not needed).
    ///
    /// All other reason codes are ignored.
    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("🔄 Audio route changed: \(reason)")
        
        // Track if engine was running before handling the change
        let wasRunning = isRunning
        
        switch reason {
        case .newDeviceAvailable:
            print("🎤 New audio device connected")
            // Reload device list when devices are added
            loadAvailableInputDevices()
            
            // If the engine was running, restart it to pick up the new device configuration
            // This ensures the audio tap is properly reconfigured for the new route
            if wasRunning {
                print("🔄 Restarting audio engine after device connection...")
                restartEngineAfterRouteChange()
            }
            
        case .oldDeviceUnavailable:
            print("🎤 Audio device disconnected")
            // Reload device list when devices are removed
            loadAvailableInputDevices()
            
            // If the engine was running, restart it to use the fallback device
            if wasRunning {
                print("🔄 Restarting audio engine after device disconnection...")
                restartEngineAfterRouteChange()
            }
            
        case .categoryChange:
            print("🎤 Audio category changed - refreshing device list")
            // Don't restart on category change as it may have been triggered by our own code
            loadAvailableInputDevices()
            
        default:
            break
        }
    }
    
    /// Restarts the audio engine 0.5 s after an iOS route change.
    ///
    /// The delay allows the audio session to settle before `stop()` / `start()`
    /// are called. After a successful restart, `routeChangeRestartCount` is
    /// incremented so that ``TapToneAnalyzer`` can reset its warm-up timer and
    /// threshold state.
    func restartEngineAfterRouteChange() {
        // Use a slight delay to allow the system to settle after the route change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // Only restart if we're still supposed to be running
            guard self.isRunning else {
                print("🔄 Skipping restart - analyzer was stopped")
                return
            }
            
            print("🔄 Performing engine restart...")
            self.stop()
            
            // Give the system a moment to clean up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                do {
                    try self.start()
                    // Notify observers that a route change restart occurred
                    // This allows TapToneAnalyzer to reset its warmup timer and threshold state
                    self.routeChangeRestartCount += 1
                    print("✅ Audio engine restarted successfully after route change (restart #\(self.routeChangeRestartCount))")
                } catch {
                    print("❌ Failed to restart audio engine: \(error)")
                }
            }
        }
    }
    #endif
    
    /// Switches the audio input to the given device.
    ///
    /// **iOS:** Calls `AVAudioSession.setPreferredInput(_:)` with the device's
    /// `port`. The engine does not need to restart.
    ///
    /// **macOS:** Stops the engine if running, sets `selectedInputDevice`
    /// (which will be applied to the AUHAL unit on the next `start()` call),
    /// and restarts the engine.
    ///
    /// The `isApplyingDeviceSwitch` guard prevents `selectedInputDevice.didSet`
    /// from triggering a second redundant restart.
    ///
    /// - Parameter device: The ``AVAudioDevice`` to use as the new input source.
    /// - Throws: An error if `device.port` is `nil` on iOS, or if the engine
    ///   fails to restart on macOS.
    func setInputDevice(_ device: AVAudioDevice) throws {
        print("🎤 Attempting to set input device to: \(device.name)")
        
        #if os(iOS)
        // On iOS, set the preferred input using AVAudioSession
        let session = AVAudioSession.sharedInstance()
        
        guard let port = device.port else {
            throw NSError(
                domain: "RealtimeFFTAnalyzer",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid audio port"]
            )
        }
        
        do {
            try session.setPreferredInput(port)
            print("✓ Successfully set input to: \(device.name)")
        } catch {
            print("⚠️ Failed to set preferred input: \(error)")
            throw error
        }
        #else
        // macOS: Need to restart the engine with new device
        let wasRunning = audioEngine.isRunning
        
        if wasRunning {
            stop()
        }
        #endif
        
        // Update the selected device — set the guard flag so didSet does not
        // trigger a second engine restart (setInputDevice manages restart itself).
        DispatchQueue.main.async {
            self.isApplyingDeviceSwitch = true
            self.selectedInputDevice = device
            self.isApplyingDeviceSwitch = false
        }
        
        #if os(macOS)
        // If it was running, restart with the new device
        if wasRunning {
            // Give the system a moment to clean up
            Thread.sleep(forTimeInterval: 0.1)
            try start()
        }
        #else
        // On iOS, just reload device list to refresh current state
        loadAvailableInputDevices()
        #endif
    }
}
