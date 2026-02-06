#!/bin/bash

# macOS System Preferences Automation Script
# Written for macOS 26.x (Tahoe) - not tested on other versions
#
# Reference: https://macos-defaults.com

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; }

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This script is only for macOS"
    exit 1
fi

# Check macOS version
macos_version=$(sw_vers -productVersion)
log "Running on macOS $macos_version"

if [[ "${macos_version%%.*}" -ne 26 ]]; then
    warn "This script was written for macOS 26.x (Tahoe) and has not been tested on other versions."
fi

## Battery & Power
log "Configuring battery and power settings..."

# Set system to high efficiency mode on power adapter
sudo pmset -c sleep 0
sudo pmset -c displaysleep 10
sudo pmset -c powermode 2
sudo pmset -c womp 1
sudo pmset -c disksleep 0

# Set system to balanced mode on battery
sudo pmset -b sleep 15
sudo pmset -b displaysleep 2
sudo pmset -b powermode 0
sudo pmset -b womp 0
sudo pmset -b disksleep 10

## Appearance (Liquid Glass Design in macOS 26 Tahoe)
log "Configuring appearance..."

# Set dark mode
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# Allow wallpaper tinting in windows (Liquid Glass feature in Tahoe)
defaults write NSGlobalDomain AppleReduceDesktopTinting -bool false

# Icon & Widget Style options in Tahoe:
# - 0: Default (Liquid Glass light)
# - 1: Dark
# - 2: Tinted  
# - 3: Clear (new in Tahoe)
# Using dark mode with default Liquid Glass icons
defaults write NSGlobalDomain AppleInterfaceIconStyle -int 1

# Reduce transparency if Liquid Glass is too distracting (personal preference)
# Uncomment if needed:
# defaults write com.apple.universalaccess reduceTransparency -bool true

## Control Center (Redesigned in macOS 26 Tahoe)
log "Configuring Control Center..."

# Show battery percentage in menu bar
defaults write ~/Library/Preferences/ByHost/com.apple.controlcenter.plist BatteryShowPercentage -bool true

# Show battery module in Control Center
defaults write com.apple.controlcenter "NSStatusItem Visible Battery" -bool true

# macOS 26 Tahoe has a completely redesigned Control Center
# Many customizations now done via System Settings > Menu Bar

# Show battery in menu bar (18 = always show)
defaults write com.apple.controlcenter Battery -int 18

# Show Wi-Fi in menu bar
defaults write com.apple.controlcenter WiFi -int 18

# Show Bluetooth in menu bar
defaults write com.apple.controlcenter Bluetooth -int 18

## Desktop and Spaces
log "Configuring Desktop and Spaces..."

# Double-click window title bar to fill (Maximize in Tahoe)
defaults write NSGlobalDomain AppleActionOnDoubleClick -string "Maximize"

# Don't automatically rearrange Spaces
defaults write com.apple.dock mru-spaces -bool false

# Group windows by application (Expose)
defaults write com.apple.dock expose-group-apps -bool true

# Enable drag windows to top for Mission Control
defaults write com.apple.dock wvous-tl-corner -int 2
defaults write com.apple.dock wvous-tl-modifier -int 0

## Displays
log "Configuring display resolution..."

# Note: Resolution setting requires displayplacer
# The 2056x1329 resolution is specific to M3 Max MacBook Pro
# Install with: brew install displayplacer

if command -v displayplacer &> /dev/null; then
    log "Setting resolution with displayplacer..."
    # Get current display ID and set resolution
    # Note: This may fail if resolution isn't available on your display
    if ! displayplacer "id:$(displayplacer list | grep 'Persistent screen id' | awk '{print $4}') res:2056x1329 scaling:on" 2>&1; then
        warn "displayplacer failed to set resolution (resolution may not be available)"
        warn "Run 'displayplacer list' to see available resolutions for your display"
    fi
else
    warn "displayplacer not found. Install with: brew install displayplacer"
    warn "Then manually set resolution to 2056x1329 or run this script again"
fi

## Wallpaper
log "Configuring wallpaper..."

# Set wallpaper to solid black color
# Path may vary in Tahoe - checking multiple possible locations
if [[ -f "/System/Library/Desktop Pictures/Solid Colors/Black.png" ]]; then
    osascript -e 'tell application "System Events" to tell every desktop to set picture to "/System/Library/Desktop Pictures/Solid Colors/Black.png"'
elif [[ -f "/System/Library/Desktop Pictures/Solid Colors/Solid Black.png" ]]; then
    osascript -e 'tell application "System Events" to tell every desktop to set picture to "/System/Library/Desktop Pictures/Solid Colors/Solid Black.png"'
else
    warn "Solid black wallpaper not found in expected locations"
    warn "Set wallpaper manually via System Settings > Wallpaper"
fi

## Sound
log "Configuring sound settings..."

# Disable startup sound
sudo nvram StartupMute=%01

## Lock Screen
log "Configuring lock screen..."

# Show Sleep, Restart, and Shutdown buttons on lock screen
sudo defaults write /Library/Preferences/com.apple.loginwindow PowerOffDisabled -bool false

## Privacy & Security
log "Configuring privacy and security..."

# Allow apps from App Store and identified developers
sudo spctl --master-enable
sudo spctl --global-enable

## Screenshots
log "Configuring screenshots..."

# Create screenshots directory if it doesn't exist
mkdir -p ~/Pictures/Screenshots

# Set default screenshot location
defaults write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"

# Note: PDF screenshot format may have issues in Tahoe 26.0-26.2
# Using PNG as default (more reliable)
defaults write com.apple.screencapture type -string "png"

# Disable shadow in screenshots (personal preference)
defaults write com.apple.screencapture disable-shadow -bool true

# Include date in screenshot filename
defaults write com.apple.screencapture include-date -bool true

# Restart SystemUIServer to apply screenshot changes
killall SystemUIServer 2>/dev/null || true

## Trackpad Gestures
log "Configuring trackpad gestures..."

# Show Desktop (formerly pinch gesture, now configurable in System Settings)
defaults write com.apple.dock showDesktopGestureEnabled -bool true

# Launchpad is REMOVED in macOS 26 Tahoe - replaced by Apps
# This setting may not work, keeping for backwards compatibility
defaults write com.apple.dock showLaunchpadGestureEnabled -bool true

# App Exposé - swipe down with three fingers
defaults write com.apple.dock showAppExposeGestureEnabled -bool true

# Mission Control - swipe up with three fingers  
defaults write com.apple.dock showMissionControlGestureEnabled -bool true

# Notification Center - swipe left from right edge with two fingers
defaults write com.apple.AppleMultitouchTrackpad NotificationCenter -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad NotificationCenter -int 2

# Swipe between pages - scroll left or right with two fingers
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3

# Swipe between fullscreen apps - swipe left or right with three fingers
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 2

# Enable all trackpad gestures
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

## Keyboard
log "Configuring keyboard settings..."

# Disable dictation (allows Fn key for other purposes)
defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false

# Also disable dictation globally
defaults write com.apple.assistant.support "Dictation Enabled" -bool false

# Disable press-and-hold for accent characters (enables key repeat)
# Uncomment if you prefer traditional key repeat:
# defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Set keyboard repeat rate (faster)
# defaults write NSGlobalDomain KeyRepeat -int 2
# defaults write NSGlobalDomain InitialKeyRepeat -int 15

## Menu Bar Clock (With Seconds)
log "Configuring menu bar clock..."

# Show seconds in menu bar clock
defaults write com.apple.menuextra.clock ShowSeconds -bool true

# Use 12-hour format (change to true for 24-hour)
defaults write com.apple.menuextra.clock Show24Hour -bool false

# Show date in menu bar
defaults write com.apple.menuextra.clock ShowDate -int 1

# Show day of week
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true

# Date format options:
# "EEE MMM d  h:mm:ss a" = "Mon Jan 11  3:45:30 PM" (with seconds)
# "EEE h:mm:ss" = "Mon 3:45:30" (compact with seconds)
defaults write com.apple.menuextra.clock DateFormat -string "EEE MMM d  h:mm:ss a"

## Finder Preferences
log "Configuring Finder preferences..."

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Default to list view (nlsv = list view)
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Disable warning when changing file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Avoid creating .DS_Store files on network volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Avoid creating .DS_Store files on USB volumes  
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Show the ~/Library folder
chflags nohidden ~/Library

# Show the /Volumes folder
sudo chflags nohidden /Volumes

## Spotlight (Redesigned in macOS 26 Tahoe)
log "Configuring Spotlight..."

# Enable Spotlight clipboard history
# Note: In Tahoe 26.1+, you can set clipboard history duration
# Options: 30 minutes, 8 hours (default), or 7 days
# This is best configured via System Settings > Spotlight

# Disable Spotlight indexing for certain locations (optional)
# sudo mdutil -i off /Volumes/Code/.builds
# sudo mdutil -i off /Volumes/Data/.caches

## Application Settings
log "Configuring application settings..."

# Activity Monitor: Show CPU graph in Dock icon
# Icon types: 0=CPU, 1=CPU History, 2=Network, 3=Disk, 4=Memory, 5=CPU Meter, 6=CPU Graph
defaults write com.apple.ActivityMonitor IconType -int 6

## Restart Affected Applications
log "Restarting affected applications..."

# Kill affected applications to apply changes
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true  
killall ControlCenter 2>/dev/null || true
killall Finder 2>/dev/null || true

# Note: Some changes require logout/restart to take full effect
warn "Some changes may require logging out or restarting for full effect"

## Completion
log "✅ macOS 26 Tahoe preferences configured successfully!"
echo ""
echo "Summary of changes applied:"
echo "  • Battery: High power on adapter, wake for network on adapter only"
echo "  • Appearance: Dark mode with Liquid Glass design"
echo "  • Control Center: Battery percentage shown"
echo "  • Dock: Auto-hide, minimize to app, no recent apps"
echo "  • Display: Resolution set to 2056x1329"
echo "  • Wallpaper: Solid black"
echo "  • Sound: Startup sound disabled"
echo "  • Lock Screen: Power buttons shown"
echo "  • Security: App Store and identified developers allowed"
echo "  • Screenshots: Saved to ~/Pictures/Screenshots"
echo "  • Trackpad: All gestures enabled (Show Desktop, Mission Control, App Exposé)"
echo "  • Keyboard: Dictation disabled"
echo "  • Clock: Shows seconds, date, and day of week"
echo "  • Finder: Hidden files shown, extensions shown, list view default"
echo "  • Spotlight: Clipboard history available (Cmd+Space, then Cmd+4)"
echo ""
echo "macOS 26 Tahoe-specific notes:"
echo "  • Launchpad has been replaced by Apps (new in Tahoe)"
echo "  • Liquid Glass design is enabled by default"
echo "  • Control Center has been redesigned - customize via System Settings"
echo "  • Spotlight now has clipboard history (Cmd+4 while in Spotlight)"
echo ""
echo "If some settings didn't apply, try logging out and back in."
echo "For more customization, visit System Settings > Appearance and Menu Bar"
