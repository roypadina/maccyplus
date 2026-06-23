#!/usr/bin/env python3
"""validate.py — CI validation for maccay-plugins.

Checks:
1. marketplace.json is valid JSON with required top-level fields.
2. Every plugin listed in marketplace.json has a corresponding plugin folder.
3. Each plugin folder contains a plugin.json with all required fields.
4. description is <= 120 characters.
5. engine is "declarative" or "javascript" (never "native").
6. engine=="javascript" plugins have an "entry" field pointing to an existing file.
7. engine=="declarative" plugins have a "declarative" field.
8. capabilities is present (may be an empty list).
9. sha256 in marketplace.json matches shasum -a 256 of the plugin's plugin.json.

Exits 0 on success. Prints a descriptive error and exits 1 on any failure.
"""

import hashlib
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKETPLACE_PATH = os.path.join(REPO_ROOT, "marketplace.json")
PLUGINS_DIR = os.path.join(REPO_ROOT, "plugins")

REQUIRED_MARKETPLACE_FIELDS = ["id", "name", "version", "plugins"]
REQUIRED_PLUGIN_FIELDS = ["id", "name", "version", "description", "kind", "engine", "capabilities"]
VALID_KINDS = {"action", "condition"}
VALID_ENGINES = {"declarative", "javascript"}
MAX_DESCRIPTION_LENGTH = 120


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def sha256_of_file(path: str) -> str:
    """Return the lowercase hex SHA-256 digest of the file at path."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_marketplace(marketplace: dict) -> None:
    for field in REQUIRED_MARKETPLACE_FIELDS:
        if field not in marketplace:
            fail(f"marketplace.json is missing required field: '{field}'")
    if not isinstance(marketplace["plugins"], list):
        fail("marketplace.json: 'plugins' must be a JSON array")


def validate_plugin_json(plugin_json_path: str, plugin_id: str) -> None:
    with open(plugin_json_path, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError as e:
            fail(f"plugin.json for '{plugin_id}' is not valid JSON: {e}")

    # Required fields
    for field in REQUIRED_PLUGIN_FIELDS:
        if field not in manifest:
            fail(f"plugin.json for '{plugin_id}' is missing required field: '{field}'")

    # Description length
    description = manifest["description"]
    if len(description) > MAX_DESCRIPTION_LENGTH:
        fail(
            f"plugin.json for '{plugin_id}': description is {len(description)} chars "
            f"(max {MAX_DESCRIPTION_LENGTH}): {description!r}"
        )

    # kind
    if manifest["kind"] not in VALID_KINDS:
        fail(
            f"plugin.json for '{plugin_id}': 'kind' must be one of {sorted(VALID_KINDS)}, "
            f"got {manifest['kind']!r}"
        )

    # engine
    if manifest["engine"] not in VALID_ENGINES:
        fail(
            f"plugin.json for '{plugin_id}': 'engine' must be one of {sorted(VALID_ENGINES)}, "
            f"got {manifest['engine']!r}. Native providers cannot be distributed as plugins."
        )

    # JavaScript plugins must have an entry field pointing to an existing file
    if manifest["engine"] == "javascript":
        if "entry" not in manifest or not manifest["entry"]:
            fail(
                f"plugin.json for '{plugin_id}': engine is 'javascript' but 'entry' field is missing or empty"
            )
        plugin_folder = os.path.dirname(plugin_json_path)
        entry_path = os.path.join(plugin_folder, manifest["entry"])
        if not os.path.isfile(entry_path):
            fail(
                f"plugin.json for '{plugin_id}': entry file '{manifest['entry']}' "
                f"does not exist at {entry_path}"
            )

    # Declarative plugins must have a declarative field
    if manifest["engine"] == "declarative":
        if "declarative" not in manifest or manifest["declarative"] is None:
            fail(
                f"plugin.json for '{plugin_id}': engine is 'declarative' but 'declarative' field is missing"
            )

    # capabilities must be a list (may be empty)
    if not isinstance(manifest["capabilities"], list):
        fail(f"plugin.json for '{plugin_id}': 'capabilities' must be a JSON array (may be empty [])")


def validate_sha256(entry: dict, plugin_json_path: str) -> None:
    plugin_id = entry["id"]
    declared_sha = entry.get("sha256", "")
    if not declared_sha:
        fail(f"marketplace.json entry for '{plugin_id}' is missing 'sha256'")

    actual_sha = sha256_of_file(plugin_json_path)
    if actual_sha != declared_sha.lower():
        fail(
            f"marketplace.json sha256 mismatch for '{plugin_id}':\n"
            f"  declared: {declared_sha}\n"
            f"  actual:   {actual_sha}\n"
            f"Re-run: shasum -a 256 {plugin_json_path}"
        )


def main() -> None:
    # Load marketplace.json
    if not os.path.isfile(MARKETPLACE_PATH):
        fail(f"marketplace.json not found at {MARKETPLACE_PATH}")

    with open(MARKETPLACE_PATH, "r", encoding="utf-8") as f:
        try:
            marketplace = json.load(f)
        except json.JSONDecodeError as e:
            fail(f"marketplace.json is not valid JSON: {e}")

    validate_marketplace(marketplace)

    errors_found = False

    for entry in marketplace["plugins"]:
        plugin_id = entry.get("id", "<missing id>")

        # Each entry needs these fields
        for field in ["id", "name", "description", "version", "kind", "source", "sha256"]:
            if field not in entry:
                print(f"ERROR: marketplace entry for '{plugin_id}' is missing field '{field}'", file=sys.stderr)
                errors_found = True

        if errors_found:
            continue

        # Derive plugin folder from source.github.path if present, else use id
        source = entry.get("source", {})
        github_source = source.get("github", {})
        plugin_path_in_repo = github_source.get("path", f"plugins/{plugin_id}")

        # The path in source is repo-relative; resolve against REPO_ROOT.
        plugin_folder_abs = os.path.join(REPO_ROOT, plugin_path_in_repo)
        plugin_json_path = os.path.join(plugin_folder_abs, "plugin.json")

        if not os.path.isdir(plugin_folder_abs):
            print(
                f"ERROR: plugin folder for '{plugin_id}' not found at {plugin_folder_abs}",
                file=sys.stderr,
            )
            errors_found = True
            continue

        if not os.path.isfile(plugin_json_path):
            print(
                f"ERROR: plugin.json for '{plugin_id}' not found at {plugin_json_path}",
                file=sys.stderr,
            )
            errors_found = True
            continue

        # Validate the plugin.json contents
        try:
            validate_plugin_json(plugin_json_path, plugin_id)
        except SystemExit:
            errors_found = True
            continue

        # Validate the sha256 hash
        try:
            validate_sha256(entry, plugin_json_path)
        except SystemExit:
            errors_found = True
            continue

        print(f"OK: {plugin_id} ({entry['version']})")

    if errors_found:
        sys.exit(1)

    print(f"\nAll {len(marketplace['plugins'])} plugin(s) passed validation.")
    sys.exit(0)


if __name__ == "__main__":
    main()
