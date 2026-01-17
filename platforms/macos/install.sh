#!/usr/bin/env bash

# macOS Installation Script
# - Discovers and presents available profiles
# - Handles preflight (sudo caching)
# - Installs Homebrew
# - Calls each selected profile's setup.sh

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PLATFORM_DIR="$DOTFILES_DIR/platforms/macos"
PROFILES_DIR="$PLATFORM_DIR/profiles"
PROFILES_FILE="$DOTFILES_DIR/.profiles"

# ============================================================================
# Parse flags
# ============================================================================
PROFILES=()
TEST_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            shift
            ;;
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
# Determine install vs upgrade mode
# ============================================================================
if [[ -f "$PROFILES_FILE" ]]; then
    MODE="upgrade"
else
    MODE="install"
fi

echo "Mode: $MODE"

# ============================================================================
# Profile discovery
# ============================================================================

# Discover available profiles from directory structure
# Returns: profile_id|name|description|order|required|standalone (sorted by order)
discover_profiles() {
    for profile_dir in "$PROFILES_DIR"/*/; do
        [[ ! -d "$profile_dir" ]] && continue
        local profile_id=$(basename "$profile_dir")
        local conf_file="$profile_dir/profile.conf"

        # Defaults
        local name="$profile_id"
        local description=""
        local order=50
        local required=false
        local standalone=false
        local enabled=true

        # Read profile.conf if exists
        if [[ -f "$conf_file" ]]; then
            while IFS='=' read -r key value; do
                [[ -z "$key" || "$key" =~ ^# ]] && continue
                value="${value%\"}"
                value="${value#\"}"
                case "$key" in
                    name) name="$value" ;;
                    description) description="$value" ;;
                    order) order="$value" ;;
                    required) required="$value" ;;
                    standalone) standalone="$value" ;;
                    enabled) enabled="$value" ;;
                esac
            done < "$conf_file"
        fi

        # Skip disabled profiles
        if [[ "$enabled" == "false" ]]; then
            continue
        fi

        # Skip standalone profiles (like test) unless in test mode
        if [[ "$standalone" == "true" && "$TEST_MODE" != "true" ]]; then
            continue
        fi

        echo "$profile_id|$name|$description|$order|$required|$standalone"
    done | sort -t'|' -k4 -n
}

# ============================================================================
# Profile selection (if not provided via flags)
# ============================================================================
if [[ ${#PROFILES[@]} -eq 0 ]]; then
    if [[ "$MODE" == "upgrade" && -f "$PROFILES_FILE" ]]; then
        # Upgrade mode - use saved profiles
        mapfile -t PROFILES < "$PROFILES_FILE"
        echo "Using saved profiles: ${PROFILES[*]}"
    else
        # Install mode - prompt for selection
        echo ""
        echo "Available profiles:"
        echo ""

        declare -a PROFILE_IDS=()
        declare -a REQUIRED_PROFILES=()
        MENU_NUM=0

        while IFS='|' read -r id name desc order required standalone; do
            [[ -z "$id" ]] && continue

            if [[ "$required" == "true" ]]; then
                REQUIRED_PROFILES+=("$id")
                echo "  *) $name - $desc [always included]"
            else
                MENU_NUM=$((MENU_NUM + 1))
                PROFILE_IDS+=("$id")
                echo "  $MENU_NUM) $name - $desc"
            fi
        done < <(discover_profiles)

        echo ""
        echo "Select profiles (comma-separated, e.g., 1,2):"
        echo "  Enter) Required profiles only"
        echo ""

        echo -n "Selection: "
        read -r SELECTION < /dev/tty
        echo "$SELECTION"  # Echo to log

        # Start with required profiles
        PROFILES=("${REQUIRED_PROFILES[@]}")

        if [[ -n "$SELECTION" ]]; then
            SELECTION="${SELECTION//,/ }"
            for choice in $SELECTION; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#PROFILE_IDS[@]} ]]; then
                    idx=$((choice - 1))
                    selected_id="${PROFILE_IDS[$idx]}"
                    [[ ! " ${PROFILES[*]} " =~ " $selected_id " ]] && PROFILES+=("$selected_id")
                fi
            done
        fi
    fi
fi

# Ensure required profiles are always included
while IFS='|' read -r id name desc order required standalone; do
    [[ -z "$id" ]] && continue
    if [[ "$required" == "true" && ! " ${PROFILES[*]} " =~ " $id " ]]; then
        PROFILES=("$id" "${PROFILES[@]}")
    fi
done < <(discover_profiles)

echo ""
echo "Selected profiles: ${PROFILES[*]}"

# Save profiles for future upgrades
printf '%s\n' "${PROFILES[@]}" > "$PROFILES_FILE"

# ============================================================================
# Preflight: Request permissions and setup temporary sudo
# ============================================================================
if [[ -f "$PLATFORM_DIR/preflight.sh" ]]; then
    source "$PLATFORM_DIR/preflight.sh"
    trap preflight_cleanup EXIT
fi

# ============================================================================
# Install Homebrew (if not present)
# ============================================================================
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
    echo ""
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew already installed: $BREW_BIN"
fi

# Use local cache if available
if [[ -n "$DOTFILES_SOURCE_DIR" && -d "$DOTFILES_SOURCE_DIR/.cache/homebrew" ]]; then
    export HOMEBREW_CACHE="$DOTFILES_SOURCE_DIR/.cache/homebrew"
    export HOMEBREW_NO_AUTO_UPDATE=1
    echo "Using local Homebrew cache: $HOMEBREW_CACHE"
fi

# ============================================================================
# Run each profile's setup.sh
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Running profile setup scripts"
echo "════════════════════════════════════════════════════════════"

for profile in "${PROFILES[@]}"; do
    PROFILE_DIR="$PROFILES_DIR/$profile"
    SETUP_SCRIPT="$PROFILE_DIR/setup.sh"

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        echo ""
        echo "Warning: No setup.sh found for profile '$profile', skipping..."
        continue
    fi

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "  Profile: $profile ($MODE)"
    echo "────────────────────────────────────────────────────────────"

    # Export useful variables for the profile script
    export DOTFILES_DIR
    export PROFILE_DIR
    export PROFILE_NAME="$profile"
    export DOTFILES_MODE="$MODE"

    # Run the profile's setup script with mode
    "$SETUP_SCRIPT" "$MODE"
done

# ============================================================================
# Post-install system configuration
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  System configuration"
echo "════════════════════════════════════════════════════════════"

# Enable Touch ID for sudo
SUDO_LOCAL="/etc/pam.d/sudo_local"
if [[ ! -f "$SUDO_LOCAL" ]]; then
    echo "Enabling Touch ID for sudo..."
    echo "auth       sufficient     pam_tid.so" | sudo tee "$SUDO_LOCAL" > /dev/null
    echo "  ✓ Touch ID enabled"
else
    echo "  ✓ Touch ID already configured"
fi

# Change default shell to Homebrew's zsh
HOMEBREW_ZSH="$(brew --prefix)/bin/zsh"
if [[ -x "$HOMEBREW_ZSH" ]]; then
    if ! grep -q "$HOMEBREW_ZSH" /etc/shells; then
        echo "Adding Homebrew zsh to /etc/shells..."
        echo "$HOMEBREW_ZSH" | sudo tee -a /etc/shells > /dev/null
    fi

    if [[ "$SHELL" != "$HOMEBREW_ZSH" ]]; then
        echo "Changing default shell to Homebrew zsh..."
        sudo chsh -s "$HOMEBREW_ZSH" "$USER"
    else
        echo "  ✓ Shell already set to Homebrew zsh"
    fi
fi

# Run macOS preferences
if [[ -f "$PLATFORM_DIR/preferences.sh" ]]; then
    echo ""
    echo "Applying macOS preferences..."
    "$PLATFORM_DIR/preferences.sh"
fi

# Run dock configuration
if [[ -f "$PLATFORM_DIR/dock.sh" ]]; then
    echo ""
    "$PLATFORM_DIR/dock.sh"
fi

echo ""
echo "macOS installation complete!"
