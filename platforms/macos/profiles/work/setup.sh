#!/usr/bin/env bash

# Work profile setup
# Office communication and productivity
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   PROFILE_DIR    - This profile's directory
#   PROFILE_NAME   - "work"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing work packages..."

# ============================================================================
# Install Brewfile
# ============================================================================
install_brewfile "$PROFILE_DIR/Brewfile"

# ============================================================================
# Profile-specific config overrides
# ============================================================================
if [[ -d "$PROFILE_DIR/config" ]]; then
    echo ""
    echo "Applying work config overrides..."
    apply_config_overrides "$PROFILE_DIR"
fi

echo ""
echo "Work setup complete!"
