#!/usr/bin/env bash

# Main installer: Sets up logging, detects OS, routes to platform installer
# Usage: ./install.sh [--select <name>...] [--reveal <name>...]

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

## Setup logging (tee to file while preserving /dev/tty for user input)
LOG_DIR="$DOTFILES_DIR/.state/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

# Redirect stdout/stderr to tee (logs to file + console)
exec > >(tee -a "$LOG_FILE") 2>&1

echo "════════════════════════════════════════════════════════════"
echo "  Dotfiles Installation"
echo "  $(date)"
echo "  Log: $LOG_FILE"
echo "════════════════════════════════════════════════════════════"
echo ""

## Detect OS
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

## Route to platform-specific installer
PLATFORM_INSTALLER="$DOTFILES_DIR/platforms/$OS/install.sh"

if [[ ! -f "$PLATFORM_INSTALLER" ]]; then
    echo "Error: No installer found for $OS at $PLATFORM_INSTALLER"
    exit 1
fi

echo "Running $OS installer..."
echo ""

# Pass all arguments through to platform installer
"$PLATFORM_INSTALLER" "$@"

## Completion
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Installation complete!"
echo "  Log saved to: $LOG_FILE"
echo "════════════════════════════════════════════════════════════"
echo ""

# Start a fresh login shell
if [[ "$OS" == "macos" ]]; then
    USER_SHELL=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')
else
    USER_SHELL=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)
fi
exec "${USER_SHELL:-$SHELL}" -l
