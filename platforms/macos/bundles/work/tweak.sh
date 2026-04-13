#!/usr/bin/env bash

# Work-specific config overrides.
# Patches base configs in-place for values that need to differ at work.
#
# Idempotent: each section skips if its changes are already applied.
#
# TODO: Replace with bidirectional config sync (see TODO.md) so bundle-specific
# overrides don't need per-tool tweak scripts.

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
source "$DOTFILES_DIR/scripts/lib/common.sh"

ATUIN_CONFIG="$HOME/.config/atuin/config.toml"
BASE_CONFIG="$DOTFILES_DIR/config/atuin/config.toml"

if [[ ! -f "$BASE_CONFIG" ]]; then
    echo "  No base atuin config found, skipping work tweaks"
    return 0 2>/dev/null || exit 0
fi

if [[ -L "$ATUIN_CONFIG" ]]; then
    cp -L "$ATUIN_CONFIG" "$ATUIN_CONFIG.tmp"
    rm "$ATUIN_CONFIG"
    mv "$ATUIN_CONFIG.tmp" "$ATUIN_CONFIG"
    echo "  Copied base atuin config for work customization"
fi

# Tweak: filter_mode = "host" (instead of "global")
if grep -q '^filter_mode = "global"' "$ATUIN_CONFIG" 2>/dev/null; then
    sed -i '' 's/^filter_mode = "global"/filter_mode = "host"/' "$ATUIN_CONFIG"
    echo "  Set filter_mode to host"
fi

# Tweak: drop "global" from the search filters array
if grep -q '"global"' "$ATUIN_CONFIG" 2>/dev/null; then
    sed -i '' 's/, "global"//g; s/"global", //g; s/"global"//g' "$ATUIN_CONFIG"
    echo "  Removed global from search filters"
fi
