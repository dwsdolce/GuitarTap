# Guitar Tap

Tap-tone spectrum analysis for luthiers — the native **iPhone, iPad, and Mac** app.
Tap a guitar, tonewood plate, or brace, run a high-resolution FFT, and read the
resonant peaks and material properties (Young's modulus, specific modulus, a Gore
target thickness) that guide bracing, mass, and plate thickness — the methodology
from *Contemporary Acoustic Guitar Design and Build* by Trevor Gore and Gerard Gilet.

This is the **canonical reference** for the Guitar Tap family. The other editions are
long-term parallel ports kept at numeric/behavioural parity with this app:

- **Python desktop** (Windows / macOS / Linux) — [guitar_tap](https://github.com/dwsdolce/guitar_tap)
- **Browser (PWA)** — [GuitarTapWeb](https://github.com/dwsdolce/GuitarTapWeb)

Design and cross-platform project docs (specs, parity map, roadmap) are maintained in the
project hub repo `guitar-tap-project`, not in this repo.

## Setting up on a new machine

All commands run in **bash**: Terminal on macOS, a shell on Linux, Cygwin bash (or Git Bash) on Windows. Every
repo has its own Python environment, `.venv`, made from its own requirements files; nothing uses another repo's
Python or the system's. The repo's scripts find `.venv` themselves (`.venv/bin`, or `.venv/Scripts` on Windows) and
stop if it is missing; `PYTHON=…` names another interpreter.

1. **Prerequisites:** macOS, **Xcode 27**, Python 3.14, git. For the user manual and Quick Start Guide PDFs:
   `brew install pango pandoc` and `brew install --cask basictex` (see `GuitarTap/generate-help.sh`).
2. **Python environment** — the export checker (`requirements-dev.txt`) and the manual (`requirements-docs.txt`).
   The Help build phase also runs with it, so a build needs it too:
   ```bash
   python3.14 -m venv .venv
   .venv/bin/pip install -r requirements-dev.txt -r requirements-docs.txt
   ```
3. **Xcode:** open `GuitarTap.xcodeproj`; the scheme is `guitar_tap`.
4. **VS Code** (for the Python and shell tooling): open the folder and select `.venv` as the Python interpreter.
5. **Check it works:** `Tooling/test-fast.sh`.

## Fast test run

`Tooling/test-fast.sh` runs the macOS test suite except the recording-playback regression
(`FilePlaybackRegressionTests`), which is most of the suite's time — for use while working. Run the full
suite before a commit. The same split: web `npm run test:fast`, Python `Tooling/test-fast.sh`.

## Soak / stress testing

`Tooling/deinit-soak.sh` is an on-demand **dev tool** (not CI). It builds the test
bundle once, then loops the fast suite many times, scanning for new crash reports —
surfacing the intermittent `TapToneAnalyzer.deinit` teardown race (and its kind)
that a single run hides:

```bash
./Tooling/deinit-soak.sh 300   # 300 runs
```

A green soak is **confidence, not proof**. The Python and web editions carry a
matching `Tooling/soak.sh`.

## Links

- App Store: <https://apps.apple.com/app/guitar-tap/id6759410596>
- User manual: <https://www.dolcesfogato.com/guitar_tap/manual/>
- Website: <https://www.dolcesfogato.com/guitar_tap/>

## License

Copyright © 2026 Dolce Sfogato (David Smith). All rights reserved.

<!-- When this repository is published as open source, add a LICENSE file
     (GNU General Public License v3.0, matching guitar_tap / GuitarTapWeb) and
     change this line to reference it. -->