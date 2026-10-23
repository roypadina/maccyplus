# Contributing to MaccyPlus

Thanks for your interest! Bug reports, feature ideas, docs and code are all welcome.

MaccyPlus is a fork of [Maccy](https://github.com/p0deje/Maccy). Changes that make sense for every Maccy user are better sent upstream; this repo is for what MaccyPlus adds (rules, actions, plugins, the CLI).

## Ground rules

- **`main` is protected.** Changes land via pull request and are reviewed and merged by the maintainer ([@roypadina](https://github.com/roypadina)).
- Keep changes focused. One logical change per PR, smallest diff that solves it.

## Getting started

```sh
git clone https://github.com/roypadina/maccyplus.git
cd maccyplus
Scripts/build-release.sh        # universal build + build/MaccyPlus.zip
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -only-testing:MaccyTests
```

Requirements: Xcode (macOS 14+ deployment target). New `.swift` files must be added to `Maccy.xcodeproj` (the project lists every file). `ClipboardTests` need a live pasteboard and can fail while MaccyPlus is running.

## Workflow

1. **Fork** and branch: `git checkout -b feat/my-thing`.
2. Make your change; run the tests and try it in the built app.
3. Match the surrounding style; no drive-by refactors.
4. Open a **pull request** against `main`. CI must be green and the maintainer must approve.

## Feature requests and bugs

- **Feature requests:** [open one](https://github.com/roypadina/maccyplus/issues/new?template=feature_request.yml) and say what you're trying to do; that matters more than the exact feature. Search the [open requests](https://github.com/roypadina/maccyplus/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) first and 👍 an existing one if it's there.
- **Bugs:** use the [bug report](https://github.com/roypadina/maccyplus/issues/new?template=bug_report.yml).
- **Ko-fi supporters:** add your Ko-fi name to the request and it goes to the front of my queue. It's a thank-you, not a purchase: no promise on what ships or when.
- **Bigger changes:** open an issue before the PR so we agree on the shape first. Small, focused PRs can come straight in.
- Replies are best effort, evenings and weekends. I read everything.
