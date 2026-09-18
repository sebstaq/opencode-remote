#!/usr/bin/env bash
# Verifies that the SwiftChat timeline sources vendored in
# Packages/SwiftChatTimeline are byte-identical to the pinned upstream commit.
# Run from the repo root.
set -euo pipefail

SHA=d6f54ccf9e84d2fec672b7b89d5a67dd6ee0f957
REPO=sachaservan/SwiftChat
DEST=Packages/SwiftChatTimeline/Sources/SwiftChatTimeline
URL="https://raw.githubusercontent.com/${REPO}/${SHA}"

# local-name:upstream-path:blob-sha
FILES=(
  "MessageTableView.swift:SwiftChat/Views/MessageTableView.swift:20463db8e594737160e3de030e4c54ed09ef103f"
  "ChatListView.swift:SwiftChat/Views/ChatListView.swift:cf4f5993eb32b556ea192d279c6467051642ef2f"
  "Constants.swift:SwiftChat/Config/Constants.swift:551dbb33380bd9092359df8c26696c19e9fca7e5"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for entry in "${FILES[@]}"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  path="${rest%%:*}"
  sha="${rest##*:}"
  curl -fsSL "$URL/$path" -o "$TMP/$name"
  upstream="$(git hash-object "$TMP/$name")"
  local="$(git hash-object "$DEST/$name")"
  if [ "$upstream" != "$sha" ]; then
    echo "upstream hash mismatch for $name: $upstream != $sha" >&2
    exit 1
  fi
  if [ "$local" != "$sha" ]; then
    echo "local file $DEST/$name is not byte-identical to upstream ($local != $sha)" >&2
    exit 1
  fi
  echo "verified $name ($sha)"
done
