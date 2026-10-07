---
name: maccyplus-clipboard
description: Hand Roy a value (SQL query, shell command, id, snippet) through his MaccyPlus clipboard history, labelled with this session's name and a note saying what it is and where to run it — and read, pin, move, copy, relabel or delete history items. Use whenever you would otherwise say "copied to your clipboard", `pbcopy` something for Roy, give him a query to run in DataGrip, or a command to run in another pane/terminal; also for "what's in my clipboard", "label/pin/remove that clip", "find the query from session X".
---

# MaccyPlus clipboard (agent API)

Roy runs many Claude sessions in parallel. A bare `pbcopy` loses which session a value came from
and clobbers whatever he is copying right now. Instead, leave the value in MaccyPlus history with a
**label** (who left it) and a **note** (what it is / where to run it). He sees the label as a chip on
the row, the note on hover and in the preview, and can type the label in the popup search to filter.

CLI (the app must be running; it answers in ~0.1 s, exit 2 = app not running):

```bash
M=/Applications/MaccyPlus.app/Contents/MacOS/MaccyPlus
```

## Leave a value for Roy (the main use)

1. Compute the label once per session:
   ```bash
   L=$(agentctl ls --json 2>/dev/null | python3 -c 'import json,os,sys; sid=os.environ.get("CLAUDE_CODE_SESSION_ID",""); print(next((s.get("name") or s.get("transcriptName") or "" for s in json.load(sys.stdin) if s.get("id")==sid), ""))')
   [ -n "$L" ] || L="$(basename "$PWD")·${CLAUDE_CODE_SESSION_ID:0:8}"
   ```
   Label = the session name, single line, ≤60 chars. Never put task detail in the label.
2. Add the value. Pipe multi-line values via stdin (quoting-safe); use a quoted heredoc:
   ```bash
   $M history add --label "$L" --note "DataGrip → reeco prod (read-only). Counts RD-1234 orphans." <<'EOF'
   SELECT count(*) FROM orders WHERE ...;
   EOF
   ```
   Prints the item JSON — keep its `id` to update or delete it later.
3. Tell Roy in one line: label + what it is, e.g. `In MaccyPlus: "<label>" — orphan count query (DataGrip, prod)`.

Flags on `add`:
- default: goes to the top of history **without** touching the live clipboard (safe with parallel sessions).
- `--copy`: also make it the live clipboard — only when Roy asked for it on the clipboard right now.
- `--pin`: pin it (stays in the pinned section with a letter shortcut). Use for values he'll reuse, not by default.

Note content: what it does + where to run it (`DataGrip → <db/env>`, `run in pane: ~/Code/Reeco/<repo>`,
`paste into Slack thread …`). Warn in the note if it writes data (`WRITES: updates 120 rows`).

One value per item. Several queries Roy runs separately → several `add`s, notes `1/3`, `2/3`, …

## Other commands

```bash
$M history list [--limit N] [--label L] [--search Q] [--pinned] [--full]   # newest first, text cut at 500 chars unless --full
$M history get <id>                      # full text
$M history update <id> [--label L] [--note N]   # "" clears
$M history pin <id> | unpin <id>
$M history top <id>                      # move to top of history (no clipboard change)
$M history copy <id>                     # make it the live clipboard (like Roy selecting it)
$M history delete <id>
```

Item JSON: `id, index, kind (text|image|file), title, text, label, note, pin, app, copies, firstCopiedAt, lastCopiedAt`.
Ids are stable — they survive Roy re-copying the same value. `--label` filter is case-insensitive substring.

## Rules

- **Never put secrets** (passwords, tokens, connection strings with credentials) into history — it is
  stored on disk until deleted. Say where the secret lives instead.
- Read history only for the task at hand; it holds Roy's personal copies. Don't dump it into chat.
- Never delete or relabel items you didn't add unless Roy asks.
- No `clear` command exists on purpose.
- If the CLI exits 2 (app not running), fall back to `pbcopy` and say the label/note in chat.
