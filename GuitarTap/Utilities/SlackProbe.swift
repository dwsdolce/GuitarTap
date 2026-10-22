// @parity diagnostics/slack-probe
//
//  SlackProbe.swift
//  GuitarTap
//

import Foundation
import OSLog
import QuartzCore

/// A diagnostic: how much time the main thread has to spare while audio runs. Off unless the environment variable
/// `GT_SLACK_PROBE` is `1`. Every 5 s it prints one line, in the same form in every edition:
///
/// - **lag** — a timer asks the main thread for a call every 5 ms; each call's lateness is the time the thread
///   was busy with something else.
/// - **latency** — from the audio thread handing a chunk to the main thread to the main thread taking it.
/// - **busy time** per kind of work: the main thread's per-chunk work (`main/chunk`), the capture filling done
///   on the audio thread (`accumulate`), the FFT (`fft`), the main thread's work on each FFT frame (`frame`).
///
/// With `GT_SLACK_PROBE_FFT_ON_MAIN=1` as well, the main thread also spins for the last FFT's duration after each
/// frame — the cost it would carry if the FFT ran there.
///
/// Mirrors Python `slack_probe` and the web's `slackProbe`.
final class SlackProbe: @unchecked Sendable {
    static let shared = SlackProbe()

    enum Kind: String, CaseIterable {
        case lag, latency, mainChunk = "main/chunk", accumulate, fft, frame
    }

    let enabled = ProcessInfo.processInfo.environment["GT_SLACK_PROBE"] == "1"
    let fftOnMain = ProcessInfo.processInfo.environment["GT_SLACK_PROBE_FFT_ON_MAIN"] == "1"

    private let lock = NSLock()
    private var samples: [Kind: [Double]] = [:]
    private var lastFftMs: Double = 0
    private var timer: DispatchSourceTimer?
    private var expected: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var chunkPeriodMs: Double = 0
    private static let interval: CFTimeInterval = 0.005
    private static let reportEvery: CFTimeInterval = 5
    private let logger = Logger(subsystem: "com.dolcesfogato.guitar-tap", category: "slack")

    static var now: CFTimeInterval { CACurrentMediaTime() }

    /// Starts the lag timer and the 5 s report, on the main thread. Does nothing when the probe is off.
    func start() {
        guard enabled, timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        expected = Self.now + Self.interval
        windowStart = Self.now
        t.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Records one duration (ms) of a kind of work; safe from any thread.
    func record(_ kind: Kind, ms: Double) {
        guard enabled else { return }
        lock.lock()
        samples[kind, default: []].append(ms)
        if kind == .fft { lastFftMs = ms }
        lock.unlock()
    }

    /// The audio's chunk period, for the report.
    func setChunkPeriod(samples count: Int, sampleRate: Double) {
        guard enabled, sampleRate > 0 else { return }
        chunkPeriodMs = Double(count) / sampleRate * 1000
    }

    /// Runs `work` and records its duration as `kind`.
    @discardableResult
    func time<T>(_ kind: Kind, _ work: () -> T) -> T {
        guard enabled else { return work() }
        let start = Self.now
        let result = work()
        record(kind, ms: (Self.now - start) * 1000)
        return result
    }

    /// On the main thread after each FFT frame, with `GT_SLACK_PROBE_FFT_ON_MAIN=1`: spin for the last FFT's
    /// duration.
    func simulateFftOnMain() {
        guard enabled, fftOnMain else { return }
        lock.lock(); let ms = lastFftMs; lock.unlock()
        let until = Self.now + ms / 1000
        while Self.now < until {}
    }

    private func tick() {
        let now = Self.now
        record(.lag, ms: max(0, (now - expected) * 1000))
        expected = max(expected + Self.interval, now)
        if now - windowStart >= Self.reportEvery {
            report(seconds: now - windowStart)
            windowStart = now
        }
    }

    private func report(seconds: Double) {
        lock.lock()
        let window = samples
        samples = [:]
        lock.unlock()
        func pct(_ v: [Double], _ p: Double) -> Double {
            guard !v.isEmpty else { return 0 }
            let s = v.sorted()
            return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
        }
        func f(_ x: Double) -> String { String(format: "%.2f", x) }
        var parts = ["⏱ slack \(String(format: "%.1f", seconds))s: chunk \(f(chunkPeriodMs)) ms"]
        let lag = window[.lag] ?? []
        parts.append("lag p50 \(f(pct(lag, 0.5))) p95 \(f(pct(lag, 0.95))) p99 \(f(pct(lag, 0.99))) max \(f(lag.max() ?? 0))")
        let lat = window[.latency] ?? []
        parts.append("latency p50 \(f(pct(lat, 0.5))) p95 \(f(pct(lat, 0.95))) max \(f(lat.max() ?? 0))")
        var busy = 0.0
        for kind in [Kind.mainChunk, .accumulate, .fft, .frame] {
            let v = window[kind] ?? []
            let sum = v.reduce(0, +)
            if kind == .mainChunk || kind == .frame { busy += sum }
            parts.append("\(kind.rawValue) avg \(f(v.isEmpty ? 0 : sum / Double(v.count))) max \(f(v.max() ?? 0)) n \(v.count)")
        }
        parts.append("main busy \(String(format: "%.1f", busy / (seconds * 1000) * 100))%")
        if fftOnMain { parts.append("(FFT simulated on main)") }
        let line = parts.joined(separator: " | ")
        print(line)
        fflush(stdout)
        logger.notice("\(line, privacy: .public)")
    }
}
