#!/usr/bin/env bash

# macOS Dock Configuration Script
# Customize Dock apps and settings

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[DOCK] $1${NC}"; }
warn() { echo -e "${YELLOW}[DOCK] WARNING: $1${NC}"; }

# Check if dockutil is installed
if ! command -v dockutil &> /dev/null; then
    warn "dockutil not found. Install it with: brew install dockutil"
    exit 1
fi

log "Configuring Dock..."

## Remove all existing dock items
log "Removing all existing Dock items..."

dockutil --remove all --no-restart

## Add applications to dock
log "Adding applications to Dock..."

# Helper function to add app if it exists
add_app() {
    local app_name="$1"
    local app_path="/Applications/${app_name}.app"

    if [[ -d "$app_path" ]]; then
        dockutil --add "$app_path" --no-restart
        echo "  ✓ Added: $app_name"
    else
        warn "App not found: $app_name (skipping)"
    fi
}

# Helper function to add a folder
add_folder() {
    local folder_path="$1"
    local display_type="${2:-folder}"  # folder, stack
    local sort_type="${3:-name}"       # name, dateadded, datemodified, datecreated, kind

    if [[ -d "$folder_path" ]]; then
        dockutil --add "$folder_path" --view "$display_type" --display "$sort_type" --no-restart
        echo "  ✓ Added folder: $folder_path"
    else
        warn "Folder not found: $folder_path (skipping)"
    fi
}

## Dock layout (left to right)

# Finder (always first in macOS)
add_app "Finder"

# Browser
add_app "Vivaldi"

# Communication
add_app "Slack"
add_app "Microsoft Outlook"

# Terminal
add_app "WezTerm"

# Development
add_app "Cursor"
add_app "Visual Studio Code"
add_app "Windsurf"
add_app "Antigravity"
add_app "Docker"

# AI Tools
add_app "Claude"
add_app "ChatGPT"

# Productivity
add_app "Obsidian"
add_app "Notes"

# Entertainment
add_app "Spotify"
add_app "Kindle"

## Phase 2: Bundle-specific apps (handled via override files)
# NOTE: This script includes Slack and Outlook for work environments
# For personal environment, create internal/personal/scripts/dock.sh without them
# Or replace Slack with Discord, etc.

## Optional: Add folders/special items
# Uncomment if you want these:
# add_folder "$HOME/Downloads" "stack" "dateadded"
# add_folder "$HOME/Desktop" "stack" "dateadded"
# add_folder "/Applications" "folder" "name"

## Dock settings (applied after items to prevent reset)
log "Applying Dock settings..."

# Dock size (icon size)
# defaults write com.apple.dock tilesize -int 36  # Small (more screen space)
# defaults write com.apple.dock tilesize -int 40  # Medium (most popular with devs)
# defaults write com.apple.dock tilesize -int 48    # Large (current, easier to see)
# defaults write com.apple.dock tilesize -int 64    # Extra Large (current, easier to see)

# Magnification (most developers disable this)
# defaults write com.apple.dock magnification -bool true
# defaults write com.apple.dock largesize -int 64
# defaults write com.apple.dock magnification -int 0

# Position (left, bottom, right)
defaults write com.apple.dock orientation -string "bottom"

# Auto-hide
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0.2
defaults write com.apple.dock autohide-time-modifier -float 0.4

# Show indicator lights for open applications
defaults write com.apple.dock show-process-indicators -bool true

# Don't show recent applications in Dock
defaults write com.apple.dock show-recents -bool false

# Minimize windows into application icon
defaults write com.apple.dock minimize-to-application -bool true

# Minimize effect (genie, scale, suck)
defaults write com.apple.dock mineffect -string "scale"

## Restart dock
log "Restarting Dock..."
killall Dock

log "✅ Dock configuration complete!"
echo ""
echo "Your Dock now shows (left to right):"
echo "  Finder | Vivaldi | Slack | Outlook | WezTerm | Cursor | VS Code |"
echo "  Windsurf | Antigravity | Docker | Claude | ChatGPT |"
echo "  Obsidian | Notes | Spotify | Kindle"
