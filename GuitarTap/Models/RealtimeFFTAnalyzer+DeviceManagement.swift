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
    /// Enumerates CoreAudio input devices and applies them with
    /// ``applyInputDeviceList(_:systemDefaultUID:isAutoSelectable:)``.
    ///
    /// Queries `kAudioHardwarePropertyDevices`, filters for devices with at least
    /// one input channel (`kAudioDevicePropertyStreamConfiguration`), and reads each
    /// device's display name, UID, and nominal sample rate.
    func loadAvailableInputDevicesMacOS() {
        let generation = beginDeviceListEnumeration()
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
            gtLog("⚠️ Could not get audio device count")
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
            gtLog("⚠️ Could not get audio devices")
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
            gtLog("🎤 Found input device: \(name) @ \(sampleRate) Hz (UID: \(uid))")
        }
        
        let systemDefaultUID = Self.systemDefaultInputDeviceID().flatMap { defaultID in
            devices.first(where: { $0.deviceID == defaultID })?.uid
        }
        DispatchQueue.main.async {
            self.applyEnumeratedInputDevices(devices, generation: generation,
                                             systemDefaultUID: systemDefaultUID) { device in
                // Continuity Camera/Audio devices appear autonomously whenever an iPhone is
                // nearby — switching the mic without user action mid-session is dangerous.
                // They stay listed so the user can pick them manually.
                let transport = self.transportType(for: device.deviceID)
                let isContinuity = transport == kAudioDeviceTransportTypeContinuityCaptureWired
                               || transport == kAudioDeviceTransportTypeContinuityCaptureWireless
                if isContinuity {
                    gtLog("🎤 Continuity Audio device appeared (not auto-selected): \(device.name)")
                }
                return !isContinuity
            }
        }
        
        gtLog("🎤 Found \(devices.count) audio input device(s) total")
    }

    /// The input device to use from `devices`: the saved device when it is present, otherwise
    /// the system default input, otherwise the first device. Nil when there are no devices.
    static func inputDeviceToUse(in devices: [AVAudioDevice], savedUID: String?,
                                 systemDefaultUID: String?) -> AVAudioDevice? {
        if let savedUID, let saved = devices.first(where: { $0.uid == savedUID }) {
            return saved
        }
        if let systemDefaultUID, let systemDefault = devices.first(where: { $0.uid == systemDefaultUID }) {
            return systemDefault
        }
        return devices.first
    }

    /// Applies a freshly enumerated device list to `availableInputDevices` and the selection.
    ///
    /// - The first list: selects ``inputDeviceToUse(in:savedUID:systemDefaultUID:)``.
    /// - A new device that `isAutoSelectable` accepts: selects it.
    /// - The selected device is gone: selects the system default, otherwise the first device.
    ///
    /// Every selection is saved (`selectedInputDevice.didSet`), so what Settings shows is what the
    /// next launch uses. `CADefaultDeviceAggregate` devices — transient macOS routing devices, never
    /// a user selection — are dropped first.
    func applyInputDeviceList(_ enumerated: [AVAudioDevice], systemDefaultUID: String?,
                              isAutoSelectable: (AVAudioDevice) -> Bool = { _ in true }) {
        let previousDevices = availableInputDevices
        let devices = enumerated.filter { !$0.uid.contains("CADefaultDeviceAggregate") }
        availableInputDevices = devices

        if previousDevices.isEmpty {
            let savedUID = TapDisplaySettings.selectedInputDeviceUID
            guard let device = Self.inputDeviceToUse(in: devices, savedUID: savedUID,
                                                     systemDefaultUID: systemDefaultUID) else { return }
            selectedInputDevice = device
            if device.uid == savedUID {
                gtLog("🎤 Restored previously selected mic: \(device.name)")
            } else {
                gtLog("🎤 Saved mic not connected — selected: \(device.name)")
            }
            return
        }

        let newlyConnected = devices.filter { device in
            !previousDevices.contains(where: { $0.uid == device.uid })
        }
        if let firstNew = newlyConnected.first(where: isAutoSelectable) {
            selectedInputDevice = firstNew
            gtLog("🎤 New device connected, selected: \(firstNew.name)")
        } else if let current = selectedInputDevice,
                  !devices.contains(where: { $0.uid == current.uid }) {
            selectedInputDevice = Self.inputDeviceToUse(in: devices, savedUID: nil,
                                                        systemDefaultUID: systemDefaultUID)
            gtLog("🎤 '\(current.name)' disconnected, switched to: \(selectedInputDevice?.name ?? "none")")
        }
    }

    /// Applies an enumerated device list — unless a newer enumeration has begun since, in which
    /// case this list is stale (a device in it may already be gone) and the newer one will be
    /// applied instead. Enumerations run off the main queue and are applied on it, so two quick
    /// hot-plug events can apply an older list after a newer one was read.
    func applyEnumeratedInputDevices(_ devices: [AVAudioDevice], generation: Int,
                                     systemDefaultUID: String?,
                                     isAutoSelectable: (AVAudioDevice) -> Bool = { _ in true }) {
        guard isCurrentDeviceListGeneration(generation) else {
            gtLog("🎤 Device list superseded by a newer enumeration — not applied")
            return
        }
        applyInputDeviceList(devices, systemDefaultUID: systemDefaultUID, isAutoSelectable: isAutoSelectable)
    }

    /// The device to fall back to when `failed` could not be opened, decided when the failure
    /// happens: the device the engine last opened, if it is still listed; otherwise the system
    /// default, otherwise the first listed device — never `failed` itself.
    func fallbackAfterFailedOpen(of failed: AVAudioDevice?, systemDefaultUID: String?) -> AVAudioDevice? {
        let candidates = availableInputDevices.filter { $0.uid != failed?.uid }
        if let last = lastOpenedInputDevice,
           let listed = candidates.first(where: { $0.uid == last.uid }) {
            return listed
        }
        return Self.inputDeviceToUse(in: candidates, savedUID: nil, systemDefaultUID: systemDefaultUID)
    }

    /// A restart after a selection change failed: select the fallback (reported by
    /// `revertFailedInputSwitch`), and start the engine on it — through the watchdog's bounded
    /// retries if that start fails too. The engine is marked as failed until a start succeeds,
    /// so a later selection starts it (``restartsOnSelectionChange(isRunning:startFailed:)``).
    func recoverFromFailedStart() {
        engineStartFailed = true
        let failed = selectedInputDevice
        let systemDefaultUID = Self.systemDefaultInputDeviceID().flatMap { defaultID in
            availableInputDevices.first(where: { $0.deviceID == defaultID })?.uid
        }
        revertFailedInputSwitch(from: failed,
                                to: fallbackAfterFailedOpen(of: failed, systemDefaultUID: systemDefaultUID))
        do {
            try start()
        } catch {
            gtLog("❌ Could not start on '\(selectedInputDevice?.name ?? "none")' either (\(error)) — retrying")
            isRecoveringEngine = true
            attemptWatchdogRecovery()
        }
    }

    /// The CoreAudio system default input device, or nil if it cannot be read.
    static func systemDefaultInputDeviceID() -> AudioDeviceID? {
        var defaultDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDeviceID
        )
        return status == noErr && defaultDeviceID != 0 ? defaultDeviceID : nil
    }

    /// Returns the CoreAudio transport type for the given device, or
    /// `kAudioDeviceTransportTypeUnknown` if the property cannot be read.
    ///
    /// Used to distinguish Continuity Audio devices (which appear autonomously
    /// due to iPhone proximity) from deliberately connected USB/Bluetooth devices.
    private func transportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return transport
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
            gtLog("⚠️ Failed to register CoreAudio device change listener: \(status)")
        } else {
            gtLog("✅ Registered CoreAudio device change listener")
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
            gtLog("🔄 Sample rate changed on device \(deviceID) — restarting engine if running")
            // Weak at every hop, like the listener block itself. This is a stored CoreAudio
            // listener that can fire during teardown; an implicit strong capture here would pin
            // the analyzer alive across the queue hop and stop/restart it even after everything
            // else had released it, which is exactly what the outer `[weak self]` exists to avoid.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    do {
                        try self.start()
                        self.routeChangeRestartCount += 1
                        gtLog("✅ Engine restarted after sample rate change (restart #\(self.routeChangeRestartCount))")
                    } catch {
                        gtLog("❌ Failed to restart engine after sample rate change: \(error)")
                    }
                }
            }
        }
        sampleRateListenerBlock = block
        sampleRateListenerDeviceID = deviceID
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
        if status == noErr {
            gtLog("✅ Registered sample rate listener for device \(deviceID)")
        } else {
            gtLog("⚠️ Failed to register sample rate listener for device \(deviceID): \(status)")
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

    /// Looks up the CoreAudio `AudioDeviceID` for a given device UID string.
    ///
    /// Used by `start()` to resolve the persisted device UID from UserDefaults
    /// when `selectedInputDevice` hasn't been assigned yet (the async device
    /// enumeration hasn't completed).
    ///
    /// - Parameter uid: The device UID string (e.g. from `kAudioDevicePropertyDeviceUID`).
    /// - Returns: The matching `AudioDeviceID`, or `nil` if not found.
    static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        // Enumerate all devices and match by UID.
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for devID in deviceIDs {
            var cfUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(devID, &uidAddr, 0, nil, &uidSize, &cfUID) == noErr,
               let deviceUID = cfUID?.takeUnretainedValue() as String?,
               deviceUID == uid {
                return devID
            }
        }
        return nil
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
                gtLog("🎙️ iOS audio session configured for device enumeration")
            } catch {
                gtLog("⚠️ Failed to configure audio session for device enumeration: \(error)")
                // Continue anyway - we may still get some devices
            }
        } else {
            gtLog("🎙️ Skipping audio session reconfiguration - engine is running")
        }
        
        // Get available inputs from AVAudioSession
        guard let availableInputs = session.availableInputs else {
            gtLog("⚠️ No audio inputs available")
            
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
                gtLog("⚠️ Skipping port with empty name (UID: \(port.uid))")
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
            gtLog("🎤 Found input device: \(port.portName) [\(port.portType.description)] @ \(session.sampleRate) Hz")
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
        
        gtLog("🎤 Found \(devices.count) audio input device(s) total")
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
        
        gtLog("🔄 Audio route changed: \(reason)")
        
        // Track if engine was running before handling the change
        let wasRunning = isRunning
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            loadAvailableInputDevices()
            if wasRunning {
                gtLog("🔄 Restarting audio engine after route change (\(reason))...")
                restartEngineAfterRouteChange()
            }
            
        case .categoryChange:
            // Category changes are fired by the keyboard appearing/dismissing, other
            // apps grabbing the audio session, etc.  Most of the time the actual input
            // device hasn't changed, so skip the expensive loadAvailableInputDevices()
            // call when the current route's input UID matches what we already have.
            let currentInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
            if currentInputUID == selectedInputDevice?.uid {
                gtLog("🎤 Audio category changed — input device unchanged, skipping refresh")
                break
            }
            gtLog("🎤 Audio category changed — input device differs, refreshing device list")
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
                gtLog("🔄 Skipping restart - analyzer was stopped")
                return
            }
            
            gtLog("🔄 Performing engine restart...")
            self.stop()
            
            // Give the system a moment to clean up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                do {
                    try self.start()
                    // Notify observers that a route change restart occurred
                    // This allows TapToneAnalyzer to reset its warmup timer and threshold state
                    self.routeChangeRestartCount += 1
                    gtLog("✅ Audio engine restarted successfully after route change (restart #\(self.routeChangeRestartCount))")
                } catch {
                    gtLog("❌ Failed to restart audio engine: \(error)")
                }
            }
        }
    }
    #endif
    
    /// Applies a calibration without persisting a device→calibration mapping.
    ///
    /// Used by `selectedInputDevice.didSet` when auto-loading a device-specific
    /// calibration from `CalibrationStorage`. Setting `activeCalibration` directly
    /// would trigger `activeCalibration.didSet`, which would re-save the mapping and
    /// create a redundant write. The `isLoadingDeviceCalibration` guard breaks the loop.
    func setCalibrationWithoutSavingDeviceMapping(_ calibration: MicrophoneCalibration?) {
        isLoadingDeviceCalibration = true
        activeCalibration = calibration
        isLoadingDeviceCalibration = false
    }

    /// Switches the input to `device` (a loaded measurement's microphone); it is saved, as every
    /// selection is.
    ///
    /// **iOS:** Calls `AVAudioSession.setPreferredInput(_:)` with the device's `port`. The
    /// engine does not need to restart.
    ///
    /// **macOS:** Stops the engine if running, sets `selectedInputDevice` — before returning,
    /// so the restart opens it and the caller reads its calibration — and restarts the engine.
    ///
    /// The `isApplyingDeviceSwitch` guard prevents `selectedInputDevice.didSet`
    /// from triggering a second redundant restart.
    ///
    /// - Parameter device: The ``AVAudioDevice`` to use as the new input source.
    /// - Throws: An error if `device.port` is `nil` on iOS, or if the engine
    ///   fails to restart on macOS.
    func setInputDevice(_ device: AVAudioDevice) throws {
        gtLog("🎤 Attempting to set input device to: \(device.name)")
        
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
            gtLog("✓ Successfully set input to: \(device.name)")
        } catch {
            gtLog("⚠️ Failed to set preferred input: \(error)")
            throw error
        }
        // The session accepted it, so it is open; select it.
        try switchInputDevice(to: device) {}
        #else
        // macOS: restart the engine on the new device; if it cannot be opened the previous one is
        // selected and restarted again, and the error is thrown.
        let wasRunning = audioEngine.isRunning
        if wasRunning {
            stop()
        }
        try switchInputDevice(to: device) {
            if wasRunning {
                // Give the system a moment to clean up
                Thread.sleep(forTimeInterval: 0.1)
                try self.start()
            }
        }
        #endif

        #if os(iOS)
        // On iOS, just reload device list to refresh current state
        loadAvailableInputDevices()
        #endif
    }

    /// Selects `device` and opens it with `open`. If opening fails, the previous device is selected
    /// again and `open` is tried once more for it, so a device that cannot be used is never left
    /// selected or saved; the error is rethrown for the caller to report.
    func switchInputDevice(to device: AVAudioDevice, open: () throws -> Void) throws {
        let previous = selectedInputDevice
        isApplyingDeviceSwitch = true
        selectedInputDevice = device
        isApplyingDeviceSwitch = false
        do {
            try open()
        } catch {
            gtLog("❌ Could not open '\(device.name)' (\(error)) — keeping '\(previous?.name ?? "none")'")
            isApplyingDeviceSwitch = true
            selectedInputDevice = previous
            isApplyingDeviceSwitch = false
            try? open()
            throw error
        }
    }


}

#if os(iOS)
// MARK: - AVAudioSession.Port Display Name

extension AVAudioSession.Port {
    /// A user-readable display string for this port type.
    ///
    /// Avoids accessing the raw value of unknown cases, which can trigger
    /// internal framework warnings on some OS versions.
    var description: String {
        switch self {
        case .builtInMic:    return "Built-in Microphone"
        case .headsetMic:    return "Headset Microphone"
        case .lineIn:        return "Line In"
        case .airPlay:       return "AirPlay"
        case .bluetoothA2DP: return "Bluetooth A2DP"
        case .bluetoothLE:   return "Bluetooth LE"
        case .bluetoothHFP:  return "Bluetooth Hands-Free"
        case .usbAudio:      return "USB Audio"
        case .carAudio:      return "CarPlay"
        case .virtual:       return "Virtual"
        default:             return "Audio Input"
        }
    }
}
#endif
