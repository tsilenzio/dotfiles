#!/usr/bin/env bash

# Apply dotfiles configuration (packages + symlinks)
# Safe to run repeatedly - used by both install.sh and `just upgrade`
#
# Usage: ./scripts/upgrade.sh [--profile <name>]

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOTFILES_DIR

# Detect OS
case "$OSTYPE" in
    darwin*) OS="macos" ;;
    linux*)  OS="linux" ;;
    *)       echo "Error: Unsupported OS: $OSTYPE"; exit 1 ;;
esac

PLATFORM_DIR="$DOTFILES_DIR/platforms/$OS"

# ============================================================================
# Parse flags
# ============================================================================
PROFILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
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
# Load or prompt for profile
# ============================================================================
PROFILE_FILE="$DOTFILES_DIR/.profile"

if [[ -z "$PROFILE" ]]; then
    # Try to load saved profile
    if [[ -f "$PROFILE_FILE" ]]; then
        PROFILE=$(cat "$PROFILE_FILE")
        echo "Using saved profile: $PROFILE"
    else
        echo "Error: No profile specified and no saved profile found."
        echo "Run 'just install' first, or use: ./scripts/upgrade.sh --profile <name>"
        exit 1
    fi
fi

# ============================================================================
# Ensure Homebrew is available
# ============================================================================
if ! command -v brew &>/dev/null; then
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        echo "Error: Homebrew not found. Run 'just install' first."
        exit 1
    fi
fi

# ============================================================================
# Configure Homebrew packages
# ============================================================================
echo ""
echo "Configuring packages..."

# Use local cache if available
if [[ -n "$DOTFILES_SOURCE_DIR" && -d "$DOTFILES_SOURCE_DIR/.cache/homebrew" ]]; then
    export HOMEBREW_CACHE="$DOTFILES_SOURCE_DIR/.cache/homebrew"
    export HOMEBREW_NO_AUTO_UPDATE=1
    echo "Using local Homebrew cache: $HOMEBREW_CACHE"
fi

# Temporarily allow errors (some packages might fail)
set +e
BUNDLE_EXIT_CODE=0

if [[ "$PROFILE" == "test" ]]; then
    brew bundle --verbose --file="$PLATFORM_DIR/Brewfile.test"
    BUNDLE_EXIT_CODE=$?
else
    # Base packages
    brew bundle --verbose --file="$PLATFORM_DIR/Brewfile"
    BUNDLE_EXIT_CODE=$?

    # Profile-specific packages
    PROFILE_BREWFILE="$PLATFORM_DIR/Brewfile.$PROFILE"
    if [[ -f "$PROFILE_BREWFILE" ]]; then
        echo ""
        echo "Configuring $PROFILE profile packages..."
        brew bundle --verbose --file="$PROFILE_BREWFILE"
    fi
fi
set -e

if [[ $BUNDLE_EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "Warning: Some packages failed to configure."
    echo "   Continuing with the rest of the setup..."
    echo ""
fi

# Kill apps that auto-launch after installation
killall "zoom.us" 2>/dev/null || true

# Refresh PATH
eval "$(brew shellenv)"

# ============================================================================
# Configure symlinks
# ============================================================================
echo ""
echo "Configuring symlinks..."

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
            echo "  ✓ $link (already configured)"
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

# Apply symlinks
safe_link "$DOTFILES_DIR/config/zsh/zshrc" "$HOME/.zshrc"
safe_link "$DOTFILES_DIR/config/zsh/zshenv" "$HOME/.zshenv"
safe_link "$DOTFILES_DIR/config/starship/starship.toml" "$HOME/.config/starship.toml"
safe_link "$DOTFILES_DIR/config/git/gitconfig" "$HOME/.gitconfig"
safe_link "$DOTFILES_DIR/config/git/gitignore" "$HOME/.gitignore"
safe_link "$DOTFILES_DIR/config/mise/config.toml" "$HOME/.config/mise/config.toml"
safe_link "$DOTFILES_DIR/config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
safe_link "$DOTFILES_DIR/config/ssh/config" "$HOME/.ssh/config"
safe_link "$DOTFILES_DIR/config/gnupg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"

echo ""
echo "Configuration complete!"
