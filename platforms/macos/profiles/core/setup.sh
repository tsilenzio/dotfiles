#!/usr/bin/env bash

# Core profile setup
# Installs essential packages and base configuration
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   PROFILE_DIR    - This profile's directory
#   PROFILE_NAME   - "core"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

# shellcheck disable=SC2034
MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing core packages..."

# ============================================================================
# Install Brewfile
# ============================================================================
install_brewfile "$PROFILE_DIR/Brewfile"

# Kill apps that auto-launch after installation
killall "zoom.us" 2>/dev/null || true

# ============================================================================
# Configure symlinks (base configs)
# ============================================================================
echo ""
echo "Configuring symlinks..."

ensure_config_dirs
link_base_configs

# Profile-specific config overrides (if any exist in this profile)
if [[ -d "$PROFILE_DIR/config" ]]; then
    echo ""
    echo "Applying profile config overrides..."
    apply_config_overrides "$PROFILE_DIR"
fi

echo ""
echo "Core setup complete!"
