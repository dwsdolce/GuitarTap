# Parity tooling

Cross-platform parity map for **GuitarTap** (Swift, canonical) ↔ **guitar_tap**
(Python) ↔ **GuitarTapWeb** (Web), generated from co-located `@parity <slug>` tags.

## The tag

Every mirrored source file carries one comment naming its **group key** (a stable,
area-namespaced kebab slug). The slug is the join key — the tools discover the paths
by grouping files that share a slug, so paths are never restated and can't disagree.

```swift
// @parity dsp/gated-fft      // Swift / TypeScript
```
```python
# @parity dsp/gated-fft       # Python
```

A file with no counterpart by design uses the reserved slug `@parity none`.

An impl tag may link its behavioural test group with an optional attribute:

```swift
// @parity dsp/gated-fft tests=test/gated-fft
// @parity dsp/material-properties tests=test/brace,test/plate
```

The generator uses that link to fill the map's **Equivalence** column — the honest
answer to "are the contents *actually* equivalent, or just co-located?" A linked
`test/*` group makes the impl group **oracle**-backed (it has a `g#-…` web oracle
test) and/or **tests**-backed (paired Swift+Python tests); unlinked groups read
**review only**. The map asserts *location*; equivalence is proven by the oracle +
paired tests, and this column shows which rows actually have that proof.

## Commands

```
python3 Tooling/parity/gen_parity_map.py            # regenerate PARITY-MAP.md + parity-index.json + TEST-COVERAGE.md's coverage block
python3 Tooling/parity/gen_parity_map.py --check    # CI: verify all three are current + no orphan/malformed slugs
python3 Tooling/parity/gen_parity_map.py --coverage # print the functional-block coverage report (read-only)
python3 Tooling/parity/gen_parity_map.py --gaps     # report testable impl groups with NO test evidence
python3 Tooling/parity/parity_lookup.py classify    # show a group's counterparts (any column)
python3 Tooling/parity/parity_lookup.py . --sort=web    # browse everything, sorted by web path
```

`--coverage` prints the **functional-block coverage report** — of the testable blocks, how many are
covered by a test group, how many are *proven on all three platforms* (≥1 linked `test/*` group that
exists in every repo), and which are gaps — plus a per-area breakdown. The same numbers are written
into `../../TEST-COVERAGE.md`'s "Current coverage state" block by `generate`, and `--check` fails if
that block drifts. `--coverage` is read-only; it never writes.

`--gaps` (also printed by `generate`/`--check`) lists **testable** impl groups
(`dsp/` `audio/` `state/` `model/` — `view/*` is UI, review-only by design) whose
equivalence is "review only", i.e. no `tests=` link to any `test/*` group. Each is a
candidate for a test back-fill or a documented, justified gap. Two "missing-coverage"
checks together: `--check` = *missing on some* platforms (orphan slugs); `--gaps` =
*missing on all* (no test evidence).

## Outputs (committed here, in the canonical repo)

- `PARITY-MAP.md` — single self-contained table; Ctrl-F any path to find its counterparts.
- `parity-index.json` — the database the lookup utility reads.

Repo roots default to this repo plus its siblings `guitar_tap` and `GuitarTapWeb`
under the same parent; override with `PARITY_SWIFT` / `PARITY_PYTHON` / `PARITY_WEB`.

## Workflow

Change/add/move a mirrored file → add or adjust its `@parity` tag in the same diff →
run the generator → commit the updated `PARITY-MAP.md` + `parity-index.json`. `--check`
fails if the committed map drifts or a slug lands in only one repo (a typo, or something
that should be `@parity none`). Design rationale: `GuitarTapWeb/PHASE6-PARITY.md` § 6-MAP.

The living **coverage reference** (the `@parity` system, equivalence levels, the
change-all-three rule, the gates, current gaps/reverse-gaps, and the full layout of where
every coverage artifact lives) is **`../../TEST-COVERAGE.md`** at the canonical repo root.