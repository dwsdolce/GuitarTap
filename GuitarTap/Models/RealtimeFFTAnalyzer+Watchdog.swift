//
//  RealtimeFFTAnalyzer+Watchdog.swift
//  GuitarTap
//
//  Audio-liveness watchdogs: recover from a silently-wedged audio I/O context.
//
//  Two distinct failure modes, both silent and both needing the same recovery:
//
//    1. NO BUFFERS — the tap stops being called at all. The spectrum freezes.
//    2. NO SIGNAL  — the tap keeps being called on schedule but every buffer is
//       empty. The spectrum keeps updating and everything looks alive; only the
//       readings are silence. Delivery-based detection cannot see this, because
//       arrival is stamped without regard to content.
//
//  Plus the notification that most often causes (2): AVAudioEngineConfigurationChange,
//  which macOS posts when the engine's I/O is reconfigured underneath it — a USB mic
//  re-enumerating, a route change, or wake from sleep. AVAudioEngine keeps running
//  against the stale context and renders zeros until the graph is rebuilt.
//
//  Symptom this fixes: the input tap stops delivering buffers with NO thrown error
//  (e.g. another app forces the shared built-in mic through a CADefaultDeviceAggregate,
//  a sleep/wake, or an OS HAL glitch — `HALB_IOThread: there already is a thread`,
//  `error 35`, a flood of `-10877`). Nothing else notices and the spectrum freezes
//  indefinitely; it only recovers by luck when an external event happens to restart
//  the engine. The watchdog detects the silence and performs a clean, bounded,
//  backed-off restart via the existing (hardened) `start()` path.
//

import Foundation
import AVFoundation
import QuartzCore

extension RealtimeFFTAnalyzer {

    /// Backoff schedule (seconds) between consecutive recovery restarts.
    private var watchdogBackoffs: [Double] { [0.5, 1.0, 2.0, 4.0] }

    /// (Re)starts the 1 Hz buffer-delivery watchdog on the main runloop.
    /// No-op safe to call repeatedly; always replaces any existing timer.
    func startBufferWatchdog() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startBufferWatchdog() }
            return
        }
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBufferWatchdog()
        }
        // .common so it keeps firing while the user interacts with menus/sliders.
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    /// Stops the watchdog (called on intentional `stop()` and before each recovery
    /// restart so it can't fire mid-cycle).
    func stopBufferWatchdog() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopBufferWatchdog() }
            return
        }
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// One watchdog tick: if the live mic engine has gone silent past the threshold,
    /// kick off a bounded recovery.
    private func checkBufferWatchdog() {
        guard isRunning, !isPlayingFile, !isRecoveringEngine, let started = engineStartTime else { return }

        #if os(macOS)
        // A permission problem (not a wedge) is handled by the post-start TCC check;
        // don't fight it. Only recover when we are actually authorized.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        #endif

        // Startup grace: let the post-start permission/TCC flow settle before acting,
        // and give a freshly-(re)started engine time to deliver its first buffer.
        guard Date().timeIntervalSince(started) > 4.0 else { return }

        let now = CACurrentMediaTime()

        // Failure mode 1: buffers stopped arriving at all.
        let starvedFor = now - lastBufferTime
        if starvedFor > watchdogSilenceThreshold, !watchdogRecoveryExhausted {
            gtLog("⏱️ Buffer watchdog: no audio for \(String(format: "%.1f", starvedFor))s while running — I/O appears wedged")
            isRecoveringEngine = true
            attemptWatchdogRecovery()
            return
        }

        // Failure mode 2: buffers still arriving on schedule, but carrying nothing.
        // Delivery looks healthy and the spectrum keeps updating, so nothing else
        // notices; every reading is silence until the app is restarted by hand.
        let deadFor = now - lastSignalTime
        if deadFor > watchdogDeadInputThreshold, !watchdogRecoveryExhausted {
            gtLog("🔇 Dead-input watchdog: buffers arriving but no signal for \(String(format: "%.1f", deadFor))s — input appears dead")
            logAudioRouteDiagnostics()
            // Tell the user, not just the log. A device-level failure cannot be fixed
            // by restarting the engine (the recorded incident needed a USB
            // re-enumeration), so recovery will exhaust its attempts and stop — and
            // the status line is then the only thing standing between the user and an
            // app that looks alive while deaf. Stays set until signal returns.
            if !inputAppearsDead { inputAppearsDead = true }
            isRecoveringEngine = true
            attemptWatchdogRecovery()
            return
        }

        // Still dead, but out of restart attempts: keep the warning up and keep
        // watching. No restart is attempted until signal returns.
        if watchdogRecoveryExhausted && (now - lastSignalTime) > watchdogDeadInputThreshold {
            if !inputAppearsDead { inputAppearsDead = true }
            return
        }

        // Healthy — signal is flowing again. Clear the warning, the recovery streak,
        // and the exhausted latch, so a later failure gets a full set of attempts.
        if inputAppearsDead { inputAppearsDead = false }

        // Real audio falsifies any earlier "permission denied" determination. Nothing
        // else clears that flag — only dismissing the alert did — so a denial inferred
        // wrongly, or one the user has since granted, would otherwise persist for the
        // life of the session while audio was demonstrably working.
        if microphonePermissionDenied {
            gtLog("✅ Receiving audio — clearing the earlier permission-denied determination")
            microphonePermissionDenied = false
        }
        if watchdogRecoveryExhausted {
            gtLog("✅ Audio input returned — dead-input warning cleared, recovery re-armed")
            watchdogRecoveryExhausted = false
        }
        if watchdogRecoveryAttempts != 0 { watchdogRecoveryAttempts = 0 }
    }

    /// Logs what the audio route actually looks like at the moment a wedge is
    /// detected: the device the AUHAL is bound to, whether that is still the device
    /// the user selected, and whether CoreAudio still considers it alive. This is
    /// the evidence that separates "the device vanished" from "the device is fine
    /// but the stream is dead", which the symptom alone cannot distinguish.
    func logAudioRouteDiagnostics() {
        #if os(macOS)
        guard let audioUnit = inputNode?.audioUnit else {
            gtLog("   route: input node has no audio unit")
            return
        }

        var boundDevice = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let getStatus = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &boundDevice,
            &size
        )
        let selected = selectedInputDevice
        gtLog("   route: AUHAL bound to device \(getStatus == noErr ? String(boundDevice) : "unknown (\(getStatus))"), selected '\(selected?.name ?? "none")' (\(selected?.deviceID.description ?? "-"))")
        if getStatus == noErr, let selected, boundDevice != selected.deviceID {
            gtLog("   route: ⚠️ MISMATCH — the engine is not bound to the selected device")
        }

        // Is the bound device still alive, and is the AUHAL still running?
        if getStatus == noErr, boundDevice != 0 {
            var aliveAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var alive: UInt32 = 0
            var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(boundDevice, &aliveAddr, 0, nil, &aliveSize, &alive) == noErr {
                gtLog("   route: bound device isAlive = \(alive)")
            }
        }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioUnitGetProperty(audioUnit, kAudioOutputUnitProperty_IsRunning,
                                kAudioUnitScope_Global, 0, &running, &runningSize) == noErr {
            gtLog("   route: AUHAL isRunning = \(running)")
        }
        #endif
    }

    /// One recovery cycle: bounded by `watchdogMaxAttempts`, backed off, and
    /// self-driving (recurses on a thrown restart so a transiently-unavailable
    /// device keeps getting retried without a busy loop).
    private func attemptWatchdogRecovery() {
        watchdogRecoveryAttempts += 1
        guard watchdogRecoveryAttempts <= watchdogMaxAttempts else {
            // Stop RESTARTING, but keep WATCHING. Stopping the timer here used to leave
            // the app permanently deaf: nothing was left to notice the input coming
            // back, so a user who fixed the microphone — reconnected it, un-muted it,
            // raised an input level — saw no change until they relaunched. The tick is
            // cheap; it now keeps evaluating and clears the warning the moment real
            // signal returns.
            gtLog("❌ Buffer watchdog: giving up on restarts after \(watchdogMaxAttempts) attempts — still watching; will clear as soon as audio returns")
            isRecoveringEngine = false
            watchdogRecoveryExhausted = true
            return
        }

        let backoff = watchdogBackoffs[min(watchdogRecoveryAttempts - 1, watchdogBackoffs.count - 1)]
        gtLog("🔄 Buffer watchdog: recovery attempt \(watchdogRecoveryAttempts)/\(watchdogMaxAttempts) in \(backoff)s")

        // Clean teardown (also stops this watchdog), then restart via the hardened path.
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + backoff) { [weak self] in
            guard let self = self else { return }
            do {
                try self.start()  // success: start() re-arms the watchdog; buffers resume → streak clears
                gtLog("✅ Buffer watchdog: engine restarted (attempt \(self.watchdogRecoveryAttempts))")
                self.isRecoveringEngine = false
            } catch {
                gtLog("⚠️ Buffer watchdog: restart failed (\(error)) — retrying")
                self.attemptWatchdogRecovery()  // bounded retry
            }
        }
    }

    // MARK: - Configuration-change recovery

    /// Observes `AVAudioEngineConfigurationChange` and rebuilds the engine.
    ///
    /// macOS posts this when the engine's I/O is reconfigured out from under it:
    /// the input device re-enumerating on the USB bus, a route change, or wake from
    /// sleep. AVAudioEngine does **not** recover on its own — it keeps running
    /// against the stale context, and the installed tap keeps firing with empty
    /// buffers indefinitely. The documented contract is to rebuild the graph and
    /// reinstall taps, which is exactly what the recovery path already does.
    ///
    /// Registered when the live-mic engine starts and removed on `stop()`, so it can
    /// never fire during an intentional stop/restart cycle or during file playback.
    func registerConfigurationChangeObserver() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.registerConfigurationChangeObserver() }
            return
        }
        unregisterConfigurationChangeObserver()
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            gtLog("🔀 AVAudioEngineConfigurationChange — audio I/O was reconfigured underneath the engine")
            self.logAudioRouteDiagnostics()

            // Ignore it unless we are actually meant to be listening: an intentional
            // stop, file playback, or an in-flight recovery all post this too.
            guard self.isRunning, !self.isPlayingFile, !self.isRecoveringEngine else {
                gtLog("   ignoring — not running live, or a recovery is already in flight")
                return
            }

            // Rebuild through the same bounded, backed-off path the watchdogs use, so
            // a device that is still settling gets retried instead of failing once.
            self.isRecoveringEngine = true
            self.watchdogRecoveryAttempts = 0
            self.attemptWatchdogRecovery()
        }
        gtLog("✅ Registered AVAudioEngineConfigurationChange observer")
    }

    /// Removes the configuration-change observer. Safe to call repeatedly.
    func unregisterConfigurationChangeObserver() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.unregisterConfigurationChangeObserver() }
            return
        }
        guard let token = configurationChangeObserver else { return }
        NotificationCenter.default.removeObserver(token)
        configurationChangeObserver = nil
    }
}