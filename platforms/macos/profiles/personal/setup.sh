#!/usr/bin/env bash

# Personal profile setup
# Gaming, entertainment, and personal apps
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   PROFILE_DIR    - This profile's directory
#   PROFILE_NAME   - "personal"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing personal packages..."

# ============================================================================
# Install Brewfile
# ============================================================================
install_brewfile "$PROFILE_DIR/Brewfile"

# ============================================================================
# Profile-specific config overrides
# ============================================================================
if [[ -d "$PROFILE_DIR/config" ]]; then
    echo ""
    echo "Applying personal config overrides..."
    apply_config_overrides "$PROFILE_DIR"
fi

# ============================================================================
# Personal-specific setup
# ============================================================================
if [[ "$MODE" == "install" ]]; then
    echo ""
    echo "First-time personal setup..."
    # Add any first-time-only setup here
fi

echo ""
echo "Personal setup complete!"
