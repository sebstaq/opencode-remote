#!/usr/bin/env bash
# Dead-code lint. Periphery builds the scheme for testing (with the same
# package-plugin and macro validation skips as the build) and exits non-zero on
# any unused declaration.
#
# - `--retain-codable-properties`: synthesized Codable reads are not recorded in
#   the index, so encode/decode-only properties would otherwise look unused.
# - `--index-exclude`: the generated OpenAPI sources live under the build's
#   BuildToolPluginIntermediates and are not ours to prune.
set -euo pipefail
cd "$(dirname "$0")/.."

exec periphery scan \
  --project OpenCodeRemote.xcodeproj \
  --schemes OpenCodeRemote \
  --strict \
  --retain-codable-properties \
  --retain-unused-imported-modules OpenCodeAPI \
  --index-exclude '**/BuildToolPluginIntermediates/**' \
  -- \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation \
  -skipMacroValidation
