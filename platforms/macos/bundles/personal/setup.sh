#!/usr/bin/env bash

# Personal bundle setup
# Gaming, entertainment, and personal apps
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   BUNDLE_DIR     - This bundle's directory
#   BUNDLE_NAME    - "personal"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

# shellcheck disable=SC2034
MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing personal packages..."

## Install Brewfile
install_brewfile "$BUNDLE_DIR/Brewfile"

## Bundle-specific config overrides
if [[ -d "$BUNDLE_DIR/config" ]]; then
    echo ""
    echo "Applying personal config overrides..."
    apply_config_overrides "$BUNDLE_DIR"
fi

## Restore file-type licenses (auto-import only)
"$DOTFILES_DIR/scripts/licenses" --auto --bundle "$BUNDLE_NAME"

echo ""
echo "Personal setup complete!"
