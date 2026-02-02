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

## Bundle-specific config overrides
if [[ -d "$BUNDLE_DIR/config" ]]; then
    echo ""
    echo "Applying work config overrides..."
    apply_config_overrides "$BUNDLE_DIR"
fi

echo ""
echo "Work setup complete!"
