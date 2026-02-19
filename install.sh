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

# Save original file descriptors (needed to restore before final exec)
exec 3>&1 4>&2

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
PLATFORM_INSTALLER="$DOTFILES_DIR/platforms/$OS/install"

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

# Restore original file descriptors (so new shell has clean stdout/stderr)
exec 1>&3 2>&4 3>&- 4>&-

# Ensure stdin is the terminal (may be a pipe if run via curl|bash)
[[ ! -t 0 ]] && [[ -e /dev/tty ]] && exec 0< /dev/tty

# Start a fresh login shell
if [[ "$OS" == "macos" ]]; then
    USER_SHELL=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')
else
    USER_SHELL=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)
fi
exec "${USER_SHELL:-$SHELL}" -l
