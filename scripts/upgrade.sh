#!/usr/bin/env bash

# Upgrade: Re-run profile setup scripts in upgrade mode
# Safe to run repeatedly
#
# Usage: ./scripts/upgrade.sh [--profile <name>...]

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOTFILES_DIR

PROFILES_FILE="$DOTFILES_DIR/.profiles"

# ============================================================================
# Detect OS
# ============================================================================
case "$OSTYPE" in
    darwin*) OS="macos" ;;
    linux*)  OS="linux" ;;
    *)       echo "Error: Unsupported OS: $OSTYPE"; exit 1 ;;
esac

PROFILES_DIR="$DOTFILES_DIR/platforms/$OS/profiles"

# ============================================================================
# Parse flags
# ============================================================================
PROFILES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILES+=("$2")
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# ============================================================================
# Load saved profiles if none specified
# ============================================================================
if [[ ${#PROFILES[@]} -eq 0 ]]; then
    if [[ -f "$PROFILES_FILE" ]]; then
        mapfile -t PROFILES < "$PROFILES_FILE"
        echo "Using saved profiles: ${PROFILES[*]}"
    else
        echo "Error: No profiles specified and no saved profiles found."
        echo "Run './install.sh' first, or use: ./scripts/upgrade.sh --profile <name>"
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
        echo "Error: Homebrew not found. Run './install.sh' first."
        exit 1
    fi
fi

# Use local cache if available
if [[ -n "$DOTFILES_SOURCE_DIR" && -d "$DOTFILES_SOURCE_DIR/.cache/homebrew" ]]; then
    export HOMEBREW_CACHE="$DOTFILES_SOURCE_DIR/.cache/homebrew"
    export HOMEBREW_NO_AUTO_UPDATE=1
    echo "Using local Homebrew cache: $HOMEBREW_CACHE"
fi

# ============================================================================
# Run each profile's setup.sh in upgrade mode
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Running profile upgrades"
echo "════════════════════════════════════════════════════════════"

# Check if profile is enabled
is_profile_enabled() {
    local profile="$1"
    local conf_file="$PROFILES_DIR/$profile/profile.conf"
    if [[ -f "$conf_file" ]] && grep -q '^enabled=false' "$conf_file"; then
        return 1
    fi
    return 0
}

for profile in "${PROFILES[@]}"; do
    PROFILE_DIR="$PROFILES_DIR/$profile"
    SETUP_SCRIPT="$PROFILE_DIR/setup.sh"

    if ! is_profile_enabled "$profile"; then
        echo ""
        echo "Skipping disabled profile: $profile"
        continue
    fi

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        echo ""
        echo "Warning: No setup.sh found for profile '$profile', skipping..."
        continue
    fi

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "  Profile: $profile (upgrade)"
    echo "────────────────────────────────────────────────────────────"

    # Export useful variables for the profile script
    export DOTFILES_DIR
    export PROFILE_DIR
    export PROFILE_NAME="$profile"
    export DOTFILES_MODE="upgrade"

    # Run the profile's setup script in upgrade mode
    "$SETUP_SCRIPT" upgrade
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Upgrade complete!"
echo "════════════════════════════════════════════════════════════"
