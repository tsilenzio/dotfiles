#!/usr/bin/env bash

# Core bundle setup
# Installs essential packages and base configuration
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   BUNDLE_DIR     - This bundle's directory
#   BUNDLE_NAME    - "core"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

# shellcheck disable=SC2034
MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing core packages..."

## Install Brewfile
install_brewfile "$BUNDLE_DIR/Brewfile"

# Kill apps that auto-launch after installation
killall "zoom.us" 2>/dev/null || true

## Strip Gatekeeper quarantine from cask apps defined in loaded Brewfiles
echo ""
echo "Clearing quarantine flags..."
cask_tokens=$(grep -h '^cask "' "$DOTFILES_DIR"/loaded/*/Brewfile 2>/dev/null | \
    sed 's/cask "\([^"]*\)".*/\1/' | sort -u | tr '\n' ' ')
if [[ -n "$cask_tokens" ]]; then
    # shellcheck disable=SC2086
    brew info --cask --json=v2 $cask_tokens 2>/dev/null | \
        tr -d '\n' | grep -oE '"app"\s*:\s*\[[^]]*\]' | grep -oE '"[^"]+\.app"' | tr -d '"' | \
        sort -u | while read -r app; do
            if [[ -d "/Applications/$app" ]]; then
                xattr -dr com.apple.quarantine "/Applications/$app" 2>/dev/null || true
            fi
        done
fi

## Configure symlinks (base configs)
echo ""
echo "Configuring symlinks..."

ensure_config_dirs
link_base_configs

# Bundle-specific config overrides (if any exist in this bundle)
if [[ -d "$BUNDLE_DIR/config" ]]; then
    echo ""
    echo "Applying bundle config overrides..."
    apply_config_overrides "$BUNDLE_DIR"
fi

## Restore file-type licenses (auto-import only)
"$DOTFILES_DIR/scripts/licenses" --auto --bundle "$BUNDLE_NAME"

echo ""
echo "Core setup complete!"
