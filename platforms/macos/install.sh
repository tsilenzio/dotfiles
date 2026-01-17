#!/usr/bin/env bash

# macOS Installation Script
# Called by root install.sh with DOTFILES_DIR set

set -e

# Verify required variables
if [[ -z "$DOTFILES_DIR" ]]; then
    echo "Error: This script should be called from the root install.sh"
    exit 1
fi

PLATFORM_DIR="$DOTFILES_DIR/platforms/macos"

# ============================================================================
# Parse flags
# ============================================================================
TEST_MODE=false
PROFILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# ============================================================================
# Select Profile
# ============================================================================
if [[ -z "$PROFILE" ]]; then
    # Interactive mode - prompt for profile
    echo ""
    echo "Select profile:"
    echo "  1) Personal"
    echo "  2) Work"
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "  3) Test (minimal packages)"
    fi
    echo ""

    # Try to read interactively via /dev/tty (works even when stdin is piped)
    PROFILE_CHOICE=""
    if [[ -r /dev/tty ]]; then
        if [[ "$TEST_MODE" == "true" ]]; then
            read -r -p "Choice [1/2/3]: " PROFILE_CHOICE < /dev/tty || true
        else
            read -r -p "Choice [1/2]: " PROFILE_CHOICE < /dev/tty || true
        fi
    fi

    if [[ -n "$PROFILE_CHOICE" ]]; then
        case $PROFILE_CHOICE in
            1) PROFILE="personal" ;;
            2) PROFILE="work" ;;
            3) [[ "$TEST_MODE" == "true" ]] && PROFILE="test" || PROFILE="personal" ;;
            *) echo "Invalid choice, defaulting to personal"; PROFILE="personal" ;;
        esac
    elif [[ -n "$DOTFILES_PROFILE" ]]; then
        # Fallback to environment variable
        echo "Using DOTFILES_PROFILE=$DOTFILES_PROFILE"
        PROFILE="$DOTFILES_PROFILE"
    else
        echo "Error: No profile selected and no TTY available."
        echo "Use --profile <name> or set DOTFILES_PROFILE=<name>"
        exit 1
    fi
fi

echo "Using profile: $PROFILE"

# Save profile for future upgrades
echo "$PROFILE" > "$DOTFILES_DIR/.profile"

# ============================================================================
# Preflight: Request permissions and setup temporary sudo
# ============================================================================
source "$PLATFORM_DIR/preflight.sh"
trap preflight_cleanup EXIT

# ============================================================================
# Install Homebrew
# ============================================================================
# Check PATH and common locations (Homebrew might be installed but not in PATH)
BREW_BIN=""
if command -v brew &>/dev/null; then
    BREW_BIN="$(command -v brew)"
elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    BREW_BIN="/usr/local/bin/brew"
    eval "$(/usr/local/bin/brew shellenv)"
fi

if [[ -z "$BREW_BIN" ]]; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this script
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew already installed"
fi

# ============================================================================
# Configure packages and symlinks (shared with upgrade.sh)
# ============================================================================
"$DOTFILES_DIR/scripts/upgrade.sh" --profile "$PROFILE"

# ============================================================================
# Enable Touch ID for sudo
# ============================================================================
# sudo_local is designed by Apple to survive system updates (unlike /etc/pam.d/sudo)
SUDO_LOCAL="/etc/pam.d/sudo_local"
if [[ ! -f "$SUDO_LOCAL" ]]; then
    echo "Enabling Touch ID for sudo..."
    echo "auth       sufficient     pam_tid.so" | sudo tee "$SUDO_LOCAL" > /dev/null
    echo "  ✓ Touch ID enabled for sudo"
else
    echo "  ✓ Touch ID for sudo already configured"
fi

# ============================================================================
# Change default shell to Homebrew's zsh
# ============================================================================
HOMEBREW_ZSH="$(brew --prefix)/bin/zsh"

# Add Homebrew zsh to allowed shells if not already there
if ! grep -q "$HOMEBREW_ZSH" /etc/shells; then
    echo "Adding Homebrew zsh to /etc/shells..."
    echo "$HOMEBREW_ZSH" | sudo tee -a /etc/shells > /dev/null
fi

# Change to Homebrew zsh if not already using it
if [[ "$SHELL" != "$HOMEBREW_ZSH" ]]; then
    echo "Changing default shell to Homebrew zsh ($HOMEBREW_ZSH)..."
    sudo chsh -s "$HOMEBREW_ZSH" "$USER"
fi

# ============================================================================
# Run macOS preferences script
# ============================================================================
if [[ -f "$PLATFORM_DIR/preferences.sh" ]]; then
    echo ""
    echo "Applying macOS preferences..."
    "$PLATFORM_DIR/preferences.sh"
fi

# ============================================================================
# Run Dock configuration script
# ============================================================================
if [[ -f "$PLATFORM_DIR/dock.sh" ]]; then
    echo ""
    "$PLATFORM_DIR/dock.sh"
fi
