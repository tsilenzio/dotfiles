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

# ============================================================================
# Install Brewfile
# ============================================================================
install_brewfile "$BUNDLE_DIR/Brewfile"

# Kill apps that auto-launch after installation
killall "zoom.us" 2>/dev/null || true

# ============================================================================
# Configure symlinks (base configs)
# ============================================================================
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

echo ""
echo "Core setup complete!"
