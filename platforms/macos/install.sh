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
# Install Homebrew packages
# ============================================================================

# Use local cache if available (for faster installs)
if [[ -n "$DOTFILES_SOURCE_DIR" && -d "$DOTFILES_SOURCE_DIR/.cache/homebrew" ]]; then
    export HOMEBREW_CACHE="$DOTFILES_SOURCE_DIR/.cache/homebrew"
    export HOMEBREW_NO_AUTO_UPDATE=1
    echo "Using local Homebrew cache: $HOMEBREW_CACHE"
fi

# Temporarily allow errors (some packages might fail)
set +e
BUNDLE_EXIT_CODE=0

if [[ "$PROFILE" == "test" ]]; then
    # Test mode: minimal packages only
    echo "Installing minimal test packages..."
    brew bundle --verbose --file="$PLATFORM_DIR/Brewfile.test"
    BUNDLE_EXIT_CODE=$?
else
    # Regular profiles: base + profile-specific
    echo "Installing base Homebrew packages..."
    brew bundle --verbose --file="$PLATFORM_DIR/Brewfile"
    BUNDLE_EXIT_CODE=$?

    PROFILE_BREWFILE="$PLATFORM_DIR/Brewfile.$PROFILE"
    if [[ -f "$PROFILE_BREWFILE" ]]; then
        echo "Installing $PROFILE profile packages..."
        brew bundle --verbose --file="$PROFILE_BREWFILE"
    else
        echo "No Brewfile.$PROFILE found, using base packages only"
    fi
fi
set -e

if [[ $BUNDLE_EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "Warning: Some Homebrew packages failed to install."
    echo "   Continuing with the rest of the setup..."
    echo ""
fi

# Kill apps that auto-launch after installation
killall "zoom.us" 2>/dev/null || true

# Refresh PATH to pick up newly installed tools
eval "$(brew shellenv)"

# ============================================================================
# Install config files (symlinks)
# ============================================================================
echo "Creating symlinks..."

# Safe symlink: backup existing file if it's not already pointing to our target
safe_link() {
    local target="$1"
    local link="$2"
    local link_dir=$(dirname "$link")

    # Create parent directory if needed
    mkdir -p "$link_dir"

    # If link exists (file or symlink)
    if [[ -e "$link" || -L "$link" ]]; then
        # If it's already a symlink to our target, skip
        if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
            echo "  ✓ $link (already linked)"
            return 0
        fi
        # Otherwise, backup the existing file/symlink
        local backup="${link}.backup.$(date +%Y%m%d-%H%M%S)"
        echo "  ⚠ Backing up $link → $backup"
        mv "$link" "$backup"
    fi

    # Create the symlink
    ln -sf "$target" "$link"
    echo "  ✓ $link → $target"
}

# Create config directories
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.config/mise"
mkdir -p "$HOME/.config/wezterm"
mkdir -p "$HOME/.ssh/sockets"
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.ssh"
chmod 700 "$HOME/.gnupg"

# Create symlinks with backup protection
safe_link "$DOTFILES_DIR/config/zsh/zshrc" "$HOME/.zshrc"
safe_link "$DOTFILES_DIR/config/zsh/zshenv" "$HOME/.zshenv"
safe_link "$DOTFILES_DIR/config/starship/starship.toml" "$HOME/.config/starship.toml"
safe_link "$DOTFILES_DIR/config/git/gitconfig" "$HOME/.gitconfig"
safe_link "$DOTFILES_DIR/config/git/gitignore" "$HOME/.gitignore"
safe_link "$DOTFILES_DIR/config/mise/config.toml" "$HOME/.config/mise/config.toml"
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
safe_link "$DOTFILES_DIR/config/ssh/config" "$HOME/.ssh/config"
safe_link "$DOTFILES_DIR/config/gnupg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"

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
