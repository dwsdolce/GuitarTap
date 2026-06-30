# App Review Reply — Guitar Tap 1.0 (macOS resubmit)

Context: iOS 1.0 (build 330) was approved. macOS 1.0 (build 330) was rejected on
2026-06-24 for two issues (Guideline 2.1(a) and Guideline 4). Both are fixed in
the resubmitted build. Paste the text below into the App Store Connect Resolution
Center reply.

---

Hello, and thank you for the detailed review.

We have resolved both issues in this build.

**Guideline 2.1(a) — "Microphone Access Required" shown after the user grants access (macOS)**

We identified and fixed the root cause. The app was acquiring the audio input
device *before* microphone authorization had completed. On some hardware this
left the input delivering silent audio after access was granted, and our
post-startup audio check then misinterpreted that silence as a denial and
displayed the alert.

The app now defers acquiring the audio input until microphone access is confirmed
as authorized, and it no longer treats the brief post-grant audio start-up as a
denial. After the user allows microphone access, the live spectrum appears
immediately with no further alert.

To verify on a clean system: reset the permission with
`tccutil reset Microphone com.dolcesfogato.GuitarTap`, launch the app, and tap
**Allow** at the prompt — the analyzer begins showing live audio with no alert.

**Guideline 4 — no way to reopen the main window after closing it (macOS)**

Guitar Tap is a single-window application on macOS, so we have updated it to quit
when the main window is closed, per your suggestion. No data is lost: measurements
are saved explicitly by the user, and settings are persisted automatically.

We are bumping the build number to 1.0.1 since the iOS version of the app was
already approved and we are including some minor fixes that affect both the iOS
and macOS versions.

We appreciate your guidance and are happy to make any further adjustments.
Thank you.
