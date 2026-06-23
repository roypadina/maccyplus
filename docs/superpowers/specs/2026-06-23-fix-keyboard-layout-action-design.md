# Fix keyboard layout (EN ⇄ HE) — transform action

## Problem

Typing in the wrong active keyboard layout produces garbled text — English
keystrokes landing as Hebrew (`akuo` → `שלום`-ish gibberish) or the reverse.
Maccy already holds the copied clip; a one-shot transform that re-maps it to the
layout the user meant saves a retype.

A separate project, `~/Code/Padina/HeEngKeyboardTranslator` (the
`KeyLayoutSwitcher` app), already owns the canonical US-QWERTY ⇄ Israeli SI-1452
character mapping and a deterministic translation engine. This feature ports
that logic into Maccy as a new clipboard transform.

## Approach

Add the layout fix as a new `TransformKind` case, reusing the existing transform
machinery (the same path as `unwrap`, `trim`, `uppercase`). It is **not** a new
`ActionType`. The mapping is ported into Maccy as a self-contained file so there
is no runtime dependency on the other project.

Rejected alternatives:

- **Read `keyboard-mapping.json` at runtime** from the `HeEngKeyboardTranslator`
  path — fragile external path, Maccy is sandboxed, and the JSON is poorer than
  the Swift map (missing geresh/gershayim handling).
- **Shell out to the `KeyLayoutSwitcher` binary** — heavyweight and requires
  that app to be installed.

## Components

### 1. `Maccy/Actions/KeyboardLayout.swift` (new)

Mirrors the shape of `TextUnwrap.swift` — a small stateless `enum` namespace.

- Two `[Character: Character]` tables, `enToHe` and `heToEn`, ported verbatim
  from the source `KeyboardMapping.swift` (the richer Swift version, including
  geresh `U+05F3` → `w` and gershayim `U+05F4` → `W`).
- `static func fix(_ text: String) -> String`:
  - Auto-detect direction by counting Hebrew unicode scalars
    (`0x0590…0x05FF`) vs Latin (`A-Z`, `a-z`).
  - `heCount > enCount` → use `heToEn`; otherwise (Latin ≥ Hebrew, incl. tie and
    all-Latin) → use `enToHe`.
  - Apply char-by-char: `table[ch] ?? ch`. Unmapped chars (digits, space,
    layout-identical symbols) pass through unchanged.
  - Empty input returns empty.

This is the same dumb, deterministic logic as the source `TranslationEngine` —
no per-word plausibility scoring.

### 2. `TransformKind` (in `Maccy/Actions/ActionRule.swift`)

Add a case:

```swift
case fixKeyboardLayout
```

with label `"Fix keyboard layout (EN ⇄ HE)"`.

### 3. `TransformAction.run` (in `Maccy/Actions/ClipboardAction.swift`)

Add to the `switch kind`:

```swift
case .fixKeyboardLayout: result = KeyboardLayout.fix(value)
```

Reuses the existing plumbing unchanged: the empty-value `noValue` guard, the
`noteAutoOutput(result)` call (so the clipboard poller's echo does not
re-trigger), `Clipboard.shared.copy(result)`, and the `textformat` icon.

## Propagation (no edits required)

`TransformKind` is `CaseIterable`. Both consumers iterate `allCases`:

- CLI `capabilities` output — `transformKinds` list (`ActionsCLI.swift:185`).
- Settings transform picker — `ForEach(TransformKind.allCases)`
  (`ActionsSettingsPane.swift:412`).

So the new transform appears in the CLI capabilities and the Settings UI picker
automatically. No CLI or UI edits.

## Data flow

```
selected clip
  → ValueClassifier.primaryString(of: item)   (trimmed previewable text)
  → KeyboardLayout.fix(value)                  (direction auto-detect + remap)
  → ActionEngine.shared.noteAutoOutput(result) (suppress echo re-trigger)
  → Clipboard.shared.copy(result)              (result on the pasteboard)
```

Identical to every other transform.

## Trigger model

Manual only. The action is available from a clip's Actions menu and via a
user-bindable per-action keyboard shortcut. **No preset rule and no auto-run** —
"text is in the wrong layout" is not reliably detectable (most mis-typed text is
byte-valid), so auto-firing would corrupt legitimately-typed clips.

## Edge cases

- **Empty value** — handled by the existing `noValue` guard in
  `TransformAction.run`.
- **Tie / mixed script** — defaults to EN→HE, matching the source engine.
- **Unmapped characters** — pass through unchanged (digits, spaces, symbols that
  are identical across layouts).

## Tests

New `MaccyTests/KeyboardLayoutTests.swift` (XCTest — matches the repo's existing
test files). Pure logic, no UI:

- Round-trip: a known English phrase → `enToHe` → `heToEn` returns the original.
- Direction auto-detect: Hebrew-majority input maps HE→EN; Latin-majority maps
  EN→HE.
- Geresh / gershayim (`U+05F3` / `U+05F4`) → `w` / `W`.
- Symbol and digit pass-through.

## Documentation

Add `fixKeyboardLayout` to the list of valid transform values in
`.claude/skills/maccy-actions/SKILL.md`.

## Out of scope (YAGNI)

- No auto-run preset rule.
- No keyboard layouts other than US-QWERTY ⇄ Israeli SI-1452.
- No per-word plausibility scoring or partial-line detection.
