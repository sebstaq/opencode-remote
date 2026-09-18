#!/usr/bin/env bash
# Fetches the pinned SwiftChat sources into third-party/swiftchat/<sha>/ and
# verifies they are byte-identical to the upstream blobs, then regenerates the
# patch of our adapted copy against the donor. Run from the repo root.
set -euo pipefail

SHA=d6f54ccf9e84d2fec672b7b89d5a67dd6ee0f957
REPO=sachaservan/SwiftChat
DEST="third-party/swiftchat/${SHA:0:7}"
URL="https://raw.githubusercontent.com/${REPO}/${SHA}"

# local-name:upstream-path:blob-sha
FILES=(
  "MessageTableView.swift:SwiftChat/Views/MessageTableView.swift:20463db8e594737160e3de030e4c54ed09ef103f"
  "ChatListView.swift:SwiftChat/Views/ChatListView.swift:cf4f5993eb32b556ea192d279c6467051642ef2f"
  "Constants.swift:SwiftChat/Config/Constants.swift:551dbb33380bd9092359df8c26696c19e9fca7e5"
)

mkdir -p "$DEST"

for entry in "${FILES[@]}"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  path="${rest%%:*}"
  sha="${rest##*:}"
  out="$DEST/$name"
  curl -fsSL "$URL/$path" -o "$out"
  actual="$(git hash-object "$out")"
  if [ "$actual" != "$sha" ]; then
    echo "hash mismatch for $name: $actual != $sha" >&2
    exit 1
  fi
  echo "verified $name ($sha)"
done

# The donor file versus our adapted copy.
if [ -f App/Features/ChatTable.swift ]; then
  diff -u "$DEST/MessageTableView.swift" App/Features/ChatTable.swift > "$DEST/PATCH.diff" || true
  echo "wrote $DEST/PATCH.diff"
fi
