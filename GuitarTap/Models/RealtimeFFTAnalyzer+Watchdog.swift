//
//  RealtimeFFTAnalyzer+Watchdog.swift
//  GuitarTap
//
//  Buffer-delivery watchdog: recovers from a silently-wedged audio I/O context.
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

        let silentFor = CACurrentMediaTime() - lastBufferTime
        guard silentFor > watchdogSilenceThreshold else {
            // Healthy — clear any prior recovery streak.
            if watchdogRecoveryAttempts != 0 { watchdogRecoveryAttempts = 0 }
            return
        }

        gtLog("⏱️ Buffer watchdog: no audio for \(String(format: "%.1f", silentFor))s while running — I/O appears wedged")
        isRecoveringEngine = true
        attemptWatchdogRecovery()
    }

    /// One recovery cycle: bounded by `watchdogMaxAttempts`, backed off, and
    /// self-driving (recurses on a thrown restart so a transiently-unavailable
    /// device keeps getting retried without a busy loop).
    private func attemptWatchdogRecovery() {
        watchdogRecoveryAttempts += 1
        guard watchdogRecoveryAttempts <= watchdogMaxAttempts else {
            gtLog("❌ Buffer watchdog: giving up after \(watchdogMaxAttempts) failed restarts — leaving engine stopped")
            isRecoveringEngine = false
            stopBufferWatchdog()
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
}