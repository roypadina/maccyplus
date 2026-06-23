# Fix keyboard layout (EN ⇄ HE) transform action — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Fix keyboard layout (EN ⇄ HE)" clipboard transform that re-maps text typed in the wrong active keyboard layout (US-QWERTY ⇄ Israeli SI-1452).

**Architecture:** The fix is a new `TransformKind` case, reusing Maccy's existing transform machinery (the same path as `unwrap`, `trim`). A self-contained `KeyboardLayout` enum holds the two character maps (ported from the standalone `KeyLayoutSwitcher` project) and a `fix(_:)` function that auto-detects direction by counting Hebrew vs Latin scalars. `TransformKind` is `CaseIterable`, so the CLI `capabilities` output and the Settings picker pick up the new case automatically.

**Tech Stack:** Swift, AppKit, Xcode project (`Maccy.xcodeproj`, scheme `Maccy`), XCTest (`MaccyTests` target). The project does **not** use Xcode synchronized file groups, so every new `.swift` file must be registered in `Maccy.xcodeproj/project.pbxproj` by hand.

## Global Constraints

- Maccy is a sandboxed macOS app — no runtime dependency on the external `HeEngKeyboardTranslator` project; the mapping is ported in-tree.
- New `.swift` files MUST be added to `Maccy.xcodeproj/project.pbxproj` in all four required places (PBXBuildFile, PBXFileReference, group child, Sources build phase) or they will not compile.
- pbxproj uses TAB indentation — match existing whitespace exactly when editing.
- Direction logic is dumb and deterministic: `heCount > enCount` → HE→EN, otherwise EN→HE. No per-word scoring.
- Manual trigger only — no preset rule, no auto-run.
- Tests use XCTest with `@testable import Maccy` (match the existing files in `MaccyTests/`).
- Test/build destination is `platform=macOS` (this is a macOS app, no simulator).

---

### Task 1: `KeyboardLayout` core mapping + `fix()` (TDD)

Self-contained translation logic with its own unit tests. No app wiring yet.

**Files:**
- Create: `Maccy/Actions/KeyboardLayout.swift`
- Create (test): `MaccyTests/KeyboardLayoutTests.swift`
- Modify: `Maccy.xcodeproj/project.pbxproj` (register both new files)

**Interfaces:**
- Produces: `enum KeyboardLayout` with `static func fix(_ text: String) -> String`. EN→HE and HE→EN are `static let enToHe`/`heToEn` of type `[Character: Character]`. `fix("")` returns `""`; unmapped characters pass through unchanged.

- [ ] **Step 1: Write the failing test**

Create `MaccyTests/KeyboardLayoutTests.swift`:

```swift
import XCTest
@testable import Maccy

final class KeyboardLayoutTests: XCTestCase {
  // Latin-majority input → EN→HE. "akuo" on a Hebrew layout is "שלום".
  func testEnglishKeystrokesToHebrew() {
    XCTAssertEqual(KeyboardLayout.fix("akuo"), "שלום")
  }

  // Hebrew-majority input → HE→EN, the inverse of the above.
  func testHebrewKeystrokesToEnglish() {
    XCTAssertEqual(KeyboardLayout.fix("שלום"), "akuo")
  }

  // Letters round-trip cleanly through both tables.
  func testLetterRoundTrip() {
    let original = "hello"
    let hebrew = KeyboardLayout.fix(original)   // EN→HE
    XCTAssertEqual(KeyboardLayout.fix(hebrew), original) // HE→EN
  }

  // Hebrew geresh/gershayim (U+05F3 / U+05F4) map to w / W.
  func testGereshAndGershayim() {
    XCTAssertEqual(KeyboardLayout.fix("\u{05F3}"), "w")
    XCTAssertEqual(KeyboardLayout.fix("\u{05F4}"), "W")
  }

  // Digits and spaces are identical across layouts → pass through.
  func testDigitsAndSpacePassThrough() {
    XCTAssertEqual(KeyboardLayout.fix("12345 67890"), "12345 67890")
  }

  // Empty input returns empty.
  func testEmptyInput() {
    XCTAssertEqual(KeyboardLayout.fix(""), "")
  }
}
```

- [ ] **Step 2: Register the test file in the pbxproj**

Open `Maccy.xcodeproj/project.pbxproj`. Make four edits, each inserting a new line immediately AFTER the matching `SorterTests.swift` line (the anchor lines are unique; preserve tab indentation exactly).

Edit A — after the PBXBuildFile entry:
```
		DA696BD22401EEE900DE80CF /* SorterTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = DA696BD12401EEE900DE80CF /* SorterTests.swift */; };
		AA01C0DE00000000000000B2 /* KeyboardLayoutTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA01C0DE00000000000000B1 /* KeyboardLayoutTests.swift */; };
```

Edit B — after the PBXFileReference entry:
```
		DA696BD12401EEE900DE80CF /* SorterTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SorterTests.swift; sourceTree = "<group>"; };
		AA01C0DE00000000000000B1 /* KeyboardLayoutTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KeyboardLayoutTests.swift; sourceTree = "<group>"; };
```

Edit C — after the MaccyTests group child entry:
```
				DA696BD12401EEE900DE80CF /* SorterTests.swift */,
				AA01C0DE00000000000000B1 /* KeyboardLayoutTests.swift */,
```

Edit D — after the MaccyTests Sources-phase entry:
```
				DA696BD22401EEE900DE80CF /* SorterTests.swift in Sources */,
				AA01C0DE00000000000000B2 /* KeyboardLayoutTests.swift in Sources */,
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -only-testing:MaccyTests/KeyboardLayoutTests 2>&1 | tail -30
```
Expected: build/compile FAILURE — `cannot find 'KeyboardLayout' in scope`. (A compile failure is the valid "red" here; `KeyboardLayout` does not exist yet.)

(Alternative: XcodeBuildMCP `test_macos` with the same scheme/destination.)

- [ ] **Step 4: Create the implementation**

Create `Maccy/Actions/KeyboardLayout.swift`:

```swift
import Foundation

// Repairs text typed in the wrong active keyboard layout by re-mapping it
// between US-QWERTY and Israeli SI-1452. Direction is auto-detected by script
// count. Ported from the standalone KeyLayoutSwitcher engine; dumb +
// deterministic, with no per-word plausibility scoring.
enum KeyboardLayout {
  // English-typed character -> Hebrew character the user intended.
  static let enToHe: [Character: Character] = [
    // letters lowercase
    "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א", "y": "ט", "u": "ו",
    "i": "ן", "o": "ם", "p": "פ",
    "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע", "h": "י", "j": "ח",
    "k": "ל", "l": "ך",
    "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ", "n": "מ", "m": "צ",
    // letters uppercase (Hebrew has no case)
    "Q": "/", "W": "'", "E": "ק", "R": "ר", "T": "א", "Y": "ט", "U": "ו",
    "I": "ן", "O": "ם", "P": "פ",
    "A": "ש", "S": "ד", "D": "ג", "F": "כ", "G": "ע", "H": "י", "J": "ח",
    "K": "ל", "L": "ך",
    "Z": "ז", "X": "ס", "C": "ב", "V": "ה", "B": "נ", "N": "מ", "M": "צ",
    // punctuation unshifted
    "`": ";", "[": "]", "]": "[",
    ";": "ף", "'": ",",
    ",": "ת", ".": "ץ", "/": ".",
    // shifted symbols that DIFFER between layouts (RTL swaps)
    "(": ")", ")": "(",
    "{": "}", "}": "{",
    "<": ">", ">": "<",
  ]

  // Hebrew-typed character -> English character the user intended.
  static let heToEn: [Character: Character] = [
    // hebrew letters
    "ש": "a", "ד": "s", "ג": "d", "כ": "f", "ע": "g", "י": "h", "ח": "j",
    "ל": "k", "ך": "l",
    "ז": "z", "ס": "x", "ב": "c", "ה": "v", "נ": "b", "מ": "n", "צ": "m",
    "ק": "e", "ר": "r", "א": "t", "ט": "y", "ו": "u", "ן": "i", "ם": "o",
    "פ": "p",
    "ף": ";", "ת": ",", "ץ": ".",
    // Hebrew-block punctuation some Hebrew layouts produce on the w-key
    // instead of ASCII apostrophe/quote.
    "׳": "w",  // U+05F3 HEBREW PUNCTUATION GERESH
    "״": "W",  // U+05F4 HEBREW PUNCTUATION GERSHAYIM (shift+w)
    // hebrew layout punctuation outputs
    "/": "q", "'": "w", ";": "`",
    "]": "[", "[": "]",
    ",": "'", ".": "/",
    // shifted swaps
    "(": ")", ")": "(",
    "{": "}", "}": "{",
    "<": ">", ">": "<",
  ]

  /// Re-map `text` to the layout the user meant. Direction auto-detected: more
  /// Hebrew letters than Latin → HE→EN, otherwise (incl. tie / all-Latin) →
  /// EN→HE. Unmapped characters pass through unchanged.
  static func fix(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    let table = countHebrew(text) > countLatin(text) ? heToEn : enToHe
    var out = String()
    out.reserveCapacity(text.count)
    for ch in text { out.append(table[ch] ?? ch) }
    return out
  }

  private static func countHebrew(_ text: String) -> Int {
    text.unicodeScalars.reduce(0) { (0x0590...0x05FF).contains($1.value) ? $0 + 1 : $0 }
  }

  private static func countLatin(_ text: String) -> Int {
    text.unicodeScalars.reduce(0) {
      (0x41...0x5A).contains($1.value) || (0x61...0x7A).contains($1.value) ? $0 + 1 : $0
    }
  }
}
```

- [ ] **Step 5: Register the source file in the pbxproj**

Open `Maccy.xcodeproj/project.pbxproj`. Make four edits, each inserting a new line immediately AFTER the matching `TextUnwrap.swift` line (preserve tab indentation exactly).

Edit A — after the PBXBuildFile entry:
```
		E5697889E51C0335BF905695 /* TextUnwrap.swift in Sources */ = {isa = PBXBuildFile; fileRef = 54E5B26E2EE4F1B9E04D38DE /* TextUnwrap.swift */; };
		AA01C0DE00000000000000A2 /* KeyboardLayout.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA01C0DE00000000000000A1 /* KeyboardLayout.swift */; };
```

Edit B — after the PBXFileReference entry:
```
		54E5B26E2EE4F1B9E04D38DE /* TextUnwrap.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Actions/TextUnwrap.swift; sourceTree = "<group>"; };
		AA01C0DE00000000000000A1 /* KeyboardLayout.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Actions/KeyboardLayout.swift; sourceTree = "<group>"; };
```

Edit C — after the Actions group child entry:
```
				54E5B26E2EE4F1B9E04D38DE /* TextUnwrap.swift */,
				AA01C0DE00000000000000A1 /* KeyboardLayout.swift */,
```

Edit D — after the Maccy Sources-phase entry:
```
				E5697889E51C0335BF905695 /* TextUnwrap.swift in Sources */,
				AA01C0DE00000000000000A2 /* KeyboardLayout.swift in Sources */,
```

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -only-testing:MaccyTests/KeyboardLayoutTests 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` — all six `KeyboardLayoutTests` pass.

- [ ] **Step 7: Commit**

```bash
git add Maccy/Actions/KeyboardLayout.swift MaccyTests/KeyboardLayoutTests.swift Maccy.xcodeproj/project.pbxproj
git commit -m "Actions: KeyboardLayout EN⇄HE mapping + fix() with tests"
```

---

### Task 2: Wire `fixKeyboardLayout` transform into the action machinery + docs

Adds the `TransformKind` case, handles it in `TransformAction`, and documents it. The Swift exhaustive `switch` makes a successful build the proof that the wiring is complete.

**Files:**
- Modify: `Maccy/Actions/ActionRule.swift` (the `TransformKind` enum, ~lines 44-62)
- Modify: `Maccy/Actions/ClipboardAction.swift` (`TransformAction.run` switch, ~lines 141-147)
- Modify: `MaccyTests/KeyboardLayoutTests.swift` (add a propagation assertion)
- Modify: `.claude/skills/maccy-actions/SKILL.md` (`TransformKinds` list, ~lines 135-136)

**Interfaces:**
- Consumes: `KeyboardLayout.fix(_:)` from Task 1; `TransformKind` (existing), `TransformAction` (existing).
- Produces: `TransformKind.fixKeyboardLayout` with `label == "Fix keyboard layout (EN ⇄ HE)"`, handled in `TransformAction.run`. Surfaces automatically in `ActionsCLI` `capabilities.transformKinds` and the Settings transform picker (both iterate `TransformKind.allCases`).

- [ ] **Step 1: Write the failing test (enum case + label propagation)**

Add to `MaccyTests/KeyboardLayoutTests.swift` (inside the class):

```swift
  // The transform is registered and labeled, so it propagates to the CLI
  // capabilities list and the Settings picker (both iterate allCases).
  func testTransformKindRegistered() {
    XCTAssertTrue(TransformKind.allCases.contains(.fixKeyboardLayout))
    XCTAssertEqual(TransformKind.fixKeyboardLayout.label, "Fix keyboard layout (EN ⇄ HE)")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -only-testing:MaccyTests/KeyboardLayoutTests 2>&1 | tail -30
```
Expected: compile FAILURE — `type 'TransformKind' has no member 'fixKeyboardLayout'`.

- [ ] **Step 3: Add the `TransformKind` case + label**

In `Maccy/Actions/ActionRule.swift`, add the case to the enum (after `case unwrap`):

```swift
enum TransformKind: String, Codable, CaseIterable, Identifiable {
  case trim
  case uppercase
  case lowercase
  case stripFormatting
  case unwrap
  case fixKeyboardLayout
```

and add its label in the `label` switch (after the `unwrap` line):

```swift
    case .unwrap: return "Unwrap (join wrapped lines)"
    case .fixKeyboardLayout: return "Fix keyboard layout (EN ⇄ HE)"
```

- [ ] **Step 4: Handle the case in `TransformAction.run`**

In `Maccy/Actions/ClipboardAction.swift`, add to the `switch kind` (after the `.unwrap` line):

```swift
    case .unwrap: result = TextUnwrap.unwrap(value)
    case .fixKeyboardLayout: result = KeyboardLayout.fix(value)
```

- [ ] **Step 5: Build to verify the wiring + run the test**

Run:
```bash
xcodebuild build -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`. (If the `TransformAction.run` switch had not handled the new case, the build would fail with `switch must be exhaustive`.)

Then the unit test:
```bash
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -only-testing:MaccyTests/KeyboardLayoutTests 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` — `testTransformKindRegistered` now passes.

- [ ] **Step 6: Document the transform in the skill**

In `.claude/skills/maccy-actions/SKILL.md`, extend the `TransformKinds` list. Change:

```
`TransformKinds`: `trim`, `uppercase`, `lowercase`, `stripFormatting`,
`unwrap` (join soft-wrapped terminal lines into one ready-to-paste command).
```

to:

```
`TransformKinds`: `trim`, `uppercase`, `lowercase`, `stripFormatting`,
`unwrap` (join soft-wrapped terminal lines into one ready-to-paste command),
`fixKeyboardLayout` (re-map text typed in the wrong layout, EN ⇄ HE; direction auto-detected).
```

- [ ] **Step 7: Commit**

```bash
git add Maccy/Actions/ActionRule.swift Maccy/Actions/ClipboardAction.swift MaccyTests/KeyboardLayoutTests.swift .claude/skills/maccy-actions/SKILL.md
git commit -m "Actions: add fixKeyboardLayout transform (EN⇄HE) + docs"
```

---

## Self-Review

**Spec coverage:**
- `KeyboardLayout.swift` (maps + `fix()`, geresh/gershayim, direction auto-detect) → Task 1.
- New `TransformKind` case + label → Task 2 Step 3.
- `TransformAction.run` wiring → Task 2 Step 4.
- Propagation to CLI/UI (no edits, via `allCases`) → verified by Task 2 Steps 1/5.
- Manual trigger only / no preset → satisfied by omission (no preset added; matches spec).
- Edge cases (empty, tie, unmapped) → Task 1 tests `testEmptyInput`, `testDigitsAndSpacePassThrough`; tie path covered by EN→HE default.
- Tests (round-trip, direction, geresh, pass-through) → Task 1 Step 1.
- SKILL.md doc → Task 2 Step 6.
- Out of scope (no auto-run, single layout pair, no scoring) → respected.

**Placeholder scan:** No TBD/TODO; all code and commands are complete and literal.

**Type consistency:** `KeyboardLayout.fix(_:)`, `enToHe`/`heToEn`, `TransformKind.fixKeyboardLayout`, and the label string `"Fix keyboard layout (EN ⇄ HE)"` are used identically across Task 1 and Task 2.

**Note on pbxproj IDs:** the placeholder hex IDs (`AA01C0DE…A1/A2/B1/B2`) are literal strings to paste — they are unique within the project. If a collision is somehow reported, change any digit to make them unique and keep the FileRef/BuildFile pair consistent across the four edits.
