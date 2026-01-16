#!/usr/bin/env bash

set -e

# Get the directory where this script lives
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# ============================================================================
# Auto-logging
# ============================================================================
LOG_DIR="$DOTFILES_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to both terminal and log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to: $LOG_FILE"
echo ""

# ============================================================================
# Temporary passwordless sudo for installation
# ============================================================================
SUDOERS_FILE="/etc/sudoers.d/dotfiles-install-temp"

cleanup_sudoers() {
    if [[ -f "$SUDOERS_FILE" ]]; then
        sudo rm -f "$SUDOERS_FILE"
        echo "Removed temporary sudoers entry"
    fi
}

# Ensure cleanup happens on exit (success, failure, or interrupt)
trap cleanup_sudoers EXIT

echo "This script requires administrator privileges."
echo "You'll be prompted once, then no more password prompts during installation."
sudo -v

# Create temporary sudoers entry for passwordless sudo
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 440 "$SUDOERS_FILE"

# Validate the sudoers file syntax
if ! sudo visudo -c -f "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "Error: Invalid sudoers syntax, removing and falling back to normal sudo"
    sudo rm -f "$SUDOERS_FILE"
fi

# ============================================================================
# Detect OS
# ============================================================================
detect_os() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

OS="$(detect_os)"

if [[ "$OS" == "unknown" ]]; then
    echo "Error: Unsupported operating system: $OSTYPE"
    exit 1
fi

echo "Detected OS: $OS"

# ============================================================================
# Run platform-specific installer
# ============================================================================
PLATFORM_INSTALLER="$DOTFILES_DIR/platforms/$OS/install.sh"

if [[ -f "$PLATFORM_INSTALLER" ]]; then
    echo ""
    echo "Running $OS installer..."
    "$PLATFORM_INSTALLER"
else
    echo "Error: No installer found for $OS at $PLATFORM_INSTALLER"
    exit 1
fi

echo ""
echo "Setup complete! Restart your terminal or run: exec zsh"
echo "Installation log saved to: $LOG_FILE"
