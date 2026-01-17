#!/usr/bin/env bash

set -e

# Get the directory where this script lives
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# Pass through flags (--test, --profile <name>)
INSTALL_FLAGS="$*"

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

echo "This script requires administrator privileges."
echo "You'll be prompted once, then no more password prompts during installation."

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
    "$PLATFORM_INSTALLER" $INSTALL_FLAGS
else
    echo "Error: No installer found for $OS at $PLATFORM_INSTALLER"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Setup complete!"
echo "  Installation log saved to: $LOG_FILE"
echo "════════════════════════════════════════════════════════════"
echo ""

# Start a fresh login shell with the user's current configured shell
# (queries the system for the current setting, as $SHELL may be stale)
if [[ "$OS" == "macos" ]]; then
    USER_SHELL=$(dscl . -read /Users/$USER UserShell 2>/dev/null | awk '{print $2}')
else
    USER_SHELL=$(getent passwd $USER 2>/dev/null | cut -d: -f7)
fi
exec "${USER_SHELL:-$SHELL}" -l
