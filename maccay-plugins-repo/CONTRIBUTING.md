# Contributing to maccay-plugins

This repository is the official Maccay plugin marketplace. All plugins listed in
`marketplace.json` have been reviewed by at least two maintainers and satisfy the
requirements below.

## Plugin requirements

### Required manifest fields

Every plugin must supply a `plugin.json` in its folder with **all** of the following
fields present and non-empty:

| Field | Type | Constraint |
|---|---|---|
| `id` | `string` | Reverse-DNS, e.g. `com.yourname.myplugin`. Must be globally unique in this repo. |
| `name` | `string` | Human-readable display name. |
| `version` | `string` | Semantic version, e.g. `"1.0.0"`. |
| `description` | `string` | **Required. Maximum 120 characters.** Shown as the GUI tooltip. |
| `kind` | `"action"` or `"condition"` | Which type of provider this plugin registers. |
| `engine` | `"declarative"` or `"javascript"` | Must never be `"native"`. |
| `capabilities` | array | Declare every capability the plugin uses. May be `[]`. |

For `engine: "javascript"` plugins, the field `entry` (e.g. `"main.js"`) is also
**required** and must match an actual file in the plugin folder.

For `engine: "declarative"` plugins, the field `declarative` is **required** and
must contain a valid transform list (for actions) or predicate tree (for conditions).

### Description length

The `description` field must be **120 characters or fewer**. Longer descriptions are
rejected by the CI validation script and the app's manifest parser.

### Declared capabilities

The `capabilities` array must declare every resource the plugin actually accesses:

| Capability | When to declare |
|---|---|
| `"network"` | Plugin sends or receives data over the network. |
| `"fileRead"` | Plugin reads files from the filesystem. |
| `"fileWrite"` | Plugin writes files to the filesystem. |
| `"storage"` | Plugin persists data between invocations. |

**No undeclared network or filesystem access is permitted.** In v1 the app does not
enforce capability isolation at the bridge level, but plugins that declare capabilities
dishonestly will be removed and the author blocked.

### Review and merge process

1. Open a pull request with your plugin folder under `plugins/<your-plugin-id>/`.
2. Add a corresponding entry to `marketplace.json` (see format below).
3. Compute the correct `sha256` value for `plugin.json` (see below).
4. Your PR must receive **at least 2 approvals** from project maintainers listed in
   `CODEOWNERS` before it can be merged.
5. `CODEOWNERS` assigns `@OWNER` as a required reviewer for all `marketplace.json`
   changes; that review counts as one of the two required approvals.

### Computing `sha256`

The `sha256` field in `marketplace.json` must exactly match the SHA-256 hash of the
plugin's `plugin.json` file (for declarative plugins) or the release tarball (for JS
plugins with multiple files). Compute it with:

```sh
shasum -a 256 plugins/<your-plugin-id>/plugin.json
```

Copy the hex string (first field of the output) into `marketplace.json`. The CI
validation script recomputes this hash and fails if it does not match.

### Adding your entry to `marketplace.json`

Add one object to the `plugins` array:

```json
{
  "id": "com.yourname.myplugin",
  "name": "My Plugin",
  "description": "One sentence, 120 chars max.",
  "version": "1.0.0",
  "minAppVersion": "2.7.0",
  "kind": "action",
  "tags": ["transform"],
  "source": {
    "github": {
      "repo": "OWNER/maccay-plugins",
      "ref": "main",
      "path": "plugins/com.yourname.myplugin"
    }
  },
  "sha256": "<hex from shasum -a 256 plugin.json>"
}
```

## What is NOT allowed

- `engine: "native"` — only the Maccay app itself can register native providers.
- Accessing network or filesystem without declaring the corresponding capability.
- Plugins that exfiltrate clipboard content to external servers.
- Obfuscated JavaScript.
- Binary files other than recognized image assets.

## Questions

Open a GitHub Discussion or issue. Do not open a PR without first confirming that
your plugin idea is in scope.
