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
# Select Profile
# ============================================================================
echo ""
echo "Select profile:"
echo "  1) Personal"
echo "  2) Work"
echo ""
read -p "Choice [1/2]: " PROFILE_CHOICE

case $PROFILE_CHOICE in
    1) PROFILE="personal" ;;
    2) PROFILE="work" ;;
    *) echo "Invalid choice, defaulting to personal"; PROFILE="personal" ;;
esac

echo "Using profile: $PROFILE"

# ============================================================================
# Install Homebrew
# ============================================================================
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this script
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        # Apple Silicon
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        # Intel Mac
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew already installed"
fi

# ============================================================================
# Install Homebrew packages
# ============================================================================
echo "Installing base Homebrew packages..."

# Temporarily allow errors (some packages might fail)
set +e
brew bundle --file="$PLATFORM_DIR/Brewfile"
BUNDLE_EXIT_CODE=$?

# Install profile-specific packages
PROFILE_BREWFILE="$PLATFORM_DIR/Brewfile.$PROFILE"
if [[ -f "$PROFILE_BREWFILE" ]]; then
    echo "Installing $PROFILE profile packages..."
    brew bundle --file="$PROFILE_BREWFILE"
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

# Backup existing files
[[ -f "$HOME/.zshrc" ]] && mv "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d-%H%M%S)"
[[ -f "$HOME/.zshenv" ]] && mv "$HOME/.zshenv" "$HOME/.zshenv.backup.$(date +%Y%m%d-%H%M%S)"

# Create config directories
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.config/mise"
mkdir -p "$HOME/.config/wezterm"

# Create symlinks
ln -sf "$DOTFILES_DIR/config/zsh/zshrc" "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/config/zsh/zshenv" "$HOME/.zshenv"
ln -sf "$DOTFILES_DIR/config/starship/starship.toml" "$HOME/.config/starship.toml"
ln -sf "$DOTFILES_DIR/config/git/gitconfig" "$HOME/.gitconfig"
ln -sf "$DOTFILES_DIR/config/git/gitignore" "$HOME/.gitignore"
ln -sf "$DOTFILES_DIR/config/mise/config.toml" "$HOME/.config/mise/config.toml"
ln -sf "$DOTFILES_DIR/config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"

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
