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

## Atuin first-time setup (register or login for history sync)
if command -v atuin &>/dev/null && [[ ! -f "$HOME/.local/share/atuin/key" ]]; then
    echo ""
    echo "Atuin shell history sync setup..."
    echo "  Options: register (new account) or login (existing account)"
    echo -n "  Setup atuin sync? [r]egister/[l]ogin/[s]kip: "
    read -r atuin_choice < /dev/tty
    case "$atuin_choice" in
        r|R|register)
            atuin register
            echo ""
            echo "Importing existing shell history..."
            atuin import auto
            echo "  Sync starts on your next shell session."
            ;;
        l|L|login)
            atuin login
            echo "  Sync starts on your next shell session."
            ;;
        *)
            echo "  Skipped. Run 'atuin register' or 'atuin login' later."
            ;;
    esac
fi

echo ""
echo "Core setup complete!"
