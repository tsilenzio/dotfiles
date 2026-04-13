#!/usr/bin/env bash

# Work bundle setup
# Office communication and productivity
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   BUNDLE_DIR     - This bundle's directory
#   BUNDLE_NAME    - "work"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

# shellcheck disable=SC2034
MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing work packages..."

## Install Brewfile
install_brewfile "$BUNDLE_DIR/Brewfile"

# Kill apps that auto-launch after installation
killall "zoom.us" 2>/dev/null || true

## Bundle-specific config tweaks
echo ""
echo "Applying work-specific config overrides..."
"$BUNDLE_DIR/tweak.sh"

echo ""
echo "Work setup complete!"
