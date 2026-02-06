#!/usr/bin/env bash

# Test bundle setup
# Minimal packages for VM testing
#
# Environment variables available:
#   DOTFILES_DIR   - Root dotfiles directory
#   BUNDLE_DIR     - This bundle's directory
#   BUNDLE_NAME    - "test"
#   DOTFILES_MODE  - "install" or "upgrade"

set -e

# shellcheck disable=SC2034
MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Installing test packages (minimal set)..."

## Install Brewfile
install_brewfile "$BUNDLE_DIR/Brewfile"

## Minimal symlinks for testing
echo ""
echo "Configuring minimal symlinks..."

ensure_config_dirs

# Only essential symlinks (subset of link_base_configs)
CONFIG_DIR="$DOTFILES_DIR/config"

[[ -f "$CONFIG_DIR/zsh/zshrc" ]] && safe_link "$CONFIG_DIR/zsh/zshrc" "$HOME/.zshrc"
[[ -f "$CONFIG_DIR/zsh/zshenv" ]] && safe_link "$CONFIG_DIR/zsh/zshenv" "$HOME/.zshenv"
[[ -f "$CONFIG_DIR/zsh/zprofile" ]] && safe_link "$CONFIG_DIR/zsh/zprofile" "$HOME/.zprofile"
[[ -f "$CONFIG_DIR/git/gitconfig" ]] && safe_link "$CONFIG_DIR/git/gitconfig" "$HOME/.gitconfig"
[[ -f "$CONFIG_DIR/git/gitignore" ]] && safe_link "$CONFIG_DIR/git/gitignore" "$HOME/.gitignore"
[[ -f "$CONFIG_DIR/gnupg/gpg-agent.conf" ]] && safe_link "$CONFIG_DIR/gnupg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"

echo ""
echo "Test setup complete!"
