# GuitarTap Release Checklist

The runbook for shipping a release. Four surfaces across three repos, all steps manual (no CI):

| Surface | Repo | Destination |
|---|---|---|
| **Mac / iOS** | `GuitarTap` | App Store Connect |
| **Python** | `guitar_tap` | GitHub `dwsdolce/guitar_tap` |
| **Web app** | `GuitarTapWeb` | `dolcesfogato.com/guitar_tap/guitar_tap_web/` |
| **Marketing site** | `guitar_tap_website` | `dolcesfogato.com/guitar_tap/` |

**The build-number rule (read once):** in every repo the build number is that repo's own
`git rev-list --count HEAD`, baked at build/archive time. So finish committing first, then build from
that commit, and keep each release-notes filename equal to the commit count you actually ship. Build
numbers differ across repos — that is expected.

> **Uploads to both `dolcesfogato.com` paths are done by hand via cPanel's File Manager** (no script,
> no CI). Tip: upload a **zip** of the folder and use File Manager → _Extract_ in place, so the swap is
> effectively atomic; then delete stale hashed assets left from the previous build.

---

## 0. Before you start
- [ ] Decide the new **marketing version** `X.Y.Z` (identical across all four surfaces).
- [ ] Each repo clean and on `main`.

## 1. Swift — Mac/iOS → App Store  *(`/Users/dws/src/GuitarTap`)*

### 1a. Version + code *(always)*
- [ ] Bump `MARKETING_VERSION` in **both** places in `GuitarTap.xcodeproj/project.pbxproj` (Debug + Release).
- [ ] Land all app code for the release.

### 1b. Build & upload for testing *(optional — TestFlight / review)*
- [ ] Xcode → **Archive** → Organizer → validate → **Upload** *(team `43QHHT3XK2`, app `id6759410596`)*.
- [ ] Add TestFlight "test notes" if needed — these are **not** the App Store release notes.
- [ ] No App Store release notes are required just to upload or test a build.

### 1c. Publish a public release *(only when shipping)*
- [ ] Update the build-less notes source `Documentation/ReleaseNotes.md`: **freeze** the current top section to its shipped literals, then add a **new top section** for `X.Y.Z` (prose + the `{{version}}/{{build}}/{{since}}` placeholder header). Build the **UserManual** target/scheme for the manual (needs `.venv` + WeasyPrint + `brew install pango`). *(The macOS build auto-stamps the release-notes PDF and regenerates the Quick-Start via `generate-help.sh` → `generate-release-notes.sh` — plain pandoc, all gitignored, nothing typed or committed.)*
- [ ] **Commit the code + notes source** — this is the commit you ship (generated docs are gitignored).
- [ ] Xcode → **Archive** this final commit → Organizer → validate → **Upload**. Confirm `CFBundleVersion` (= `git rev-list --count HEAD`) **==** the `<build>` in the release-notes filename.
- [ ] In **App Store Connect** → the app's new version:
  - [ ] **Paste** the "what's new" text into the **"What's New in This Version"** field — you type/paste into the form; do **not** attach the `.md`/`.pdf`. *(The files are your cumulative source, reused on the website + Python release.)*
  - [ ] Update **screenshots** only if the UI changed (upload from `Documentation/AppStoreImages/`).
  - [ ] Select the uploaded build → **Submit for Review**.
- [ ] After approval, **Release** the version (manually, or automatic if configured).
- [ ] Tag the shipped commit and push: `git tag X.Y.Z && git push origin X.Y.Z` — bare marketing version, matching the existing `1.0.1` tag on `dwsdolce/GuitarTap`. Provenance only (the App Store doesn't consume it, unlike the Python tag); tag the commit that actually shipped, after any re-submission.

## 2. Python → GitHub  *(`/Users/dws/src/guitar_tap`)*
- [ ] Bump `src/guitar_tap/version` to `X.Y.Z`.
- [ ] Edit the single source `docs/ReleaseNotes.md`: **freeze** the current top section (swap its `{{build}}`/`{{since}}` placeholders for the literals it shipped as), then add a **new top section** for `X.Y.Z` — the prose plus the placeholder header (`## Version {{version}} · Build {{build}}` / `### What's New Since Build {{since}}`). No build numbers are typed for the new release; they're stamped at build.
- [ ] **Commit now** (version + notes source). Build number = commit count, so commit *before* building, and build all three installers from this **same commit** or their `.<build>` suffixes diverge. (Committing rolls the count forward — fine, nothing manual changes after.)
- [ ] Build installers (each on its own OS):
  - [ ] macOS: `./packaging/build_mac` → `Guitar_Tap_VX.Y.Z.dmg` **plus** the stamped Quick-Start + release-notes PDFs, in one step *(codesign + notarize + staple; needs `notarytool-profile`, `create-dmg`, pandoc + LaTeX, WeasyPrint + Pango)*. Validate the PDFs first if you like — `./packaging/generate_release_notes.sh` and `./packaging/generate_guide.sh` run standalone.
  - [ ] Windows: `packaging\build_win.bat` → `Guitar_Tap_VX.Y.Z.exe`  *(Inno Setup 6)*
  - [ ] Linux: `./packaging/build_linux` → `guitar-tap-X.Y.Z-<arch>.AppImage`  *(`appimagetool`; build on old-glibc box)*
- [ ] Create the GitHub release: **tag = bare `X.Y.Z`** (no `v`, no build number — the in-app updater compares the tag to the `version` file). **Generate the notes before tagging** — `generate_release_notes.sh` derives "since" from the latest tag and refuses to run once the current version is tagged.
- [ ] Attach 6 assets: `.dmg`, `.exe`, `.AppImage`, `ReleaseNotes-X.Y.Z-<build>.pdf`, `GuitarTap-Quick-Start-Guide.pdf`, `GuitarTap-User-Manual.pdf`.
- [ ] **Publish as a full release** (not draft / pre-release) or `/releases/latest` and the updater ignore it.

## 3. Web app → `…/guitar_tap/guitar_tap_web/`  *(`/Users/dws/src/GuitarTapWeb`)*
- [ ] Bump `version` in `package.json`.
- [ ] Prepend the new entry to `RELEASES` in `src/components/ReleaseNotes.tsx` with `build: __APP_BUILD__` (the newest entry auto-matches the deployed build). **Freeze the previous top entry** to the literal build number it shipped as.
- [ ] `npm run typecheck && npm test && npm run lint` — all green.
- [ ] Commit. *(No build number to set by hand — the newest entry's `__APP_BUILD__` resolves at build time, so it is safe to roll the commit count forward right up to the deploy build.)*
- [ ] `npm run build`; smoke-test with `npm run preview`.
- [ ] **Upload the entire `dist/**`** (incl. `assets/` and `spectrum-processor.js`) to `…/guitar_tap/guitar_tap_web/` via **cPanel File Manager** (zip → Extract in place; delete stale old `assets/` hashes) — complete/atomic over HTTPS; a partial upload = blank page.
- [ ] Ensure the URL serves **with the trailing slash** (`base './'` requires it).
- [ ] Confirm a matching `GuitarTap-User-Manual-X.Y.Z.html` exists on the server (the app links to it by version).
- [ ] Tag the deployed commit and push: `git tag X.Y.Z && git push origin X.Y.Z` — bare marketing version, matching the existing `1.0.1` tag on `dwsdolce/GuitarTapWeb`. Provenance: marks exactly what is live at `…/guitar_tap_web/`.

## 4. Marketing website → `…/guitar_tap/`  *(`/Users/dws/src/guitar_tap_website` — its own repo `dwsdolce/guitar_tap_website`; see its `DEPLOY.md`)*
- [ ] Edit the version banner: `index.html` (~line 122, `Guitar Tap X.Y.Z is now available`) — the only hand-edited version string.
- [ ] Overwrite the two **stable-named** release-notes PDFs (the links never change, the contents do):
  - [ ] `releases/GuitarTap-Swift-Release-Notes.pdf` ← latest Swift cumulative PDF (GuitarTap repo)
  - [ ] `releases/GuitarTap-Python-Release-Notes.pdf` ← latest Python cumulative PDF (guitar_tap repo)
- [ ] Copy the regenerated **self-contained** manual into `manual/` — the versioned + `…-User-Manual.html/.pdf` "latest" (from GuitarTap's `generate-manual.sh`, which embeds all images into the HTML). Confirm `manual/index.html` targets `…-X.Y.Z.html`. **Do NOT deploy or overwrite `manual/images/`** — new manuals are self-contained; that folder is frozen, serving only the legacy 1.0/1.0.1 external-image HTML.
- [ ] Refresh `GuitarTap-Quick-Start-Guide.pdf` if changed; screenshots only if the UI changed.
- [ ] Commit + push the repo, then **upload the changed files** to `…/guitar_tap/` via **cPanel File Manager** (banner, the two release-notes PDFs, `manual/`).
- [ ] *No edits needed:* App Store URL (`id6759410596`), GitHub-releases download link, web-app link — all stable.

## 5. Post-release verification
- [ ] **Web:** hard-reload / fresh session (defeat the stale service worker); footer + Settings show `X.Y.Z (build)`; manual link resolves.
- [ ] **Python:** launch an installed build → in-app update check offers/matches `X.Y.Z`; site download links reach the new GitHub assets.
- [ ] **Site:** banner, both release-notes PDFs, and the manual all show the new version.
- [ ] **App Store:** track review status; marketing URL resolves.

## Gotchas / notes
- **Per-repo build numbers** differ across surfaces — expected, not a bug.
- **Python build number is fully automatic**: `version_build` is gitignored (build scripts regenerate it; `_version.py` resolves it live from git when run from source, so testing shows the right build with no script/wrapper). Release-notes build numbers are stamped by `generate_release_notes.sh` from the source `docs/ReleaseNotes.md` placeholders — never typed. The generated docs (`ReleaseNotes-*.md/.pdf`, the Quick-Start `.html/.pdf`) are gitignored too — regenerated each build, distributed on the website + GitHub releases — so `build_mac` leaves a clean `git status`. Only sources are tracked (`docs/ReleaseNotes.md`, `views/help_view.py`).
- **Swift docs are automatic too** (mirrors Python): release notes stamp from `Documentation/ReleaseNotes.md` via `generate-release-notes.sh`, run from `generate-help.sh` on the macOS build (best-effort — skips if pandoc/tag missing or the version is already tagged). Quick-Start, manual, and release-notes outputs are all gitignored; sources tracked are `Documentation/ReleaseNotes.md`, `GuitarTap/Views/HelpView.swift`, the manual `Documentation/Manual/ch*.md`.
- **Web release notes build auto-binds**: the newest `RELEASES` entry uses `build: __APP_BUILD__`, so it always equals the deployed About line — nothing to set by hand. When adding a NEWER version, give it `__APP_BUILD__` and freeze the prior top entry to its literal shipped build.
- **Stale service worker (web):** `autoUpdate` means a returning visitor may need one reload before the new build takes; always hard-reload to verify a deploy, don't conclude from a first load.
- **One-time tooling per build machine:**
  - Swift docs: pango + WeasyPrint venv, pandoc, basictex.
  - Python (Mac build machine): `pip install -e ".[packaging]"`, `create-dmg`, Apple Developer ID certs + `notarytool-profile`, WeasyPrint + Pango (guide), pandoc + LaTeX (release notes). Windows: Inno Setup 6. Linux: `appimagetool` (+ `libfuse2`).
  - Web: Node.
- **Automation candidate (future):** this process is heavily manual — three separate version bumps,
  ad-hoc PDF exports, per-platform installer builds, hand-assembled GitHub assets, and cPanel uploads
  to two paths. Consolidating/scripting it is a natural scope for the **project hub repo** (STATUS item 5).
