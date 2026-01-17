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
# Profile helper functions
# ============================================================================

# Get profile config value
get_profile_conf() {
    local profile_id="$1"
    local key="$2"
    local default="${3:-}"
    local conf_file="$PROFILES_DIR/$profile_id/profile.conf"
    local value="$default"

    if [[ -f "$conf_file" ]]; then
        while IFS='=' read -r k v; do
            [[ -z "$k" || "$k" =~ ^# ]] && continue
            v="${v%\"}"
            v="${v#\"}"
            if [[ "$k" == "$key" ]]; then
                value="$v"
                break
            fi
        done < "$conf_file"
    fi

    echo "$value"
}

# Check if profile exists and is enabled
is_profile_available() {
    local profile_id="$1"
    local profile_dir="$PROFILES_DIR/$profile_id"

    [[ ! -d "$profile_dir" ]] && return 1

    local enabled=$(get_profile_conf "$profile_id" "enabled" "true")
    [[ "$enabled" == "false" ]] && return 1

    return 0
}

# Resolve dependencies for a list of profiles (recursive)
resolve_dependencies() {
    local -a input_profiles=("$@")
    local -a resolved=()
    local -a seen=()

    resolve_one() {
        local profile="$1"

        for p in "${resolved[@]}"; do
            [[ "$p" == "$profile" ]] && return 0
        done

        for p in "${seen[@]}"; do
            if [[ "$p" == "$profile" ]]; then
                echo "Error: Circular dependency detected involving '$profile'" >&2
                return 1
            fi
        done

        seen+=("$profile")

        if ! is_profile_available "$profile"; then
            echo "Error: Profile '$profile' not found or disabled" >&2
            return 1
        fi

        local requires=$(get_profile_conf "$profile" "requires" "")
        if [[ -n "$requires" ]]; then
            IFS=',' read -ra deps <<< "$requires"
            for dep in "${deps[@]}"; do
                dep="${dep// /}"
                [[ -n "$dep" ]] && resolve_one "$dep"
            done
        fi

        resolved+=("$profile")
    }

    for profile in "${input_profiles[@]}"; do
        resolve_one "$profile" || return 1
    done

    printf '%s\n' "${resolved[@]}"
}

# Sort profiles by order
sort_by_order() {
    local -a profiles=()
    while IFS= read -r profile; do
        [[ -n "$profile" ]] && profiles+=("$profile")
    done

    for profile in "${profiles[@]}"; do
        local order=$(get_profile_conf "$profile" "order" "50")
        echo "$order|$profile"
    done | sort -t'|' -k1 -n | cut -d'|' -f2
}

# ============================================================================
# Parse flags
# ============================================================================
PROFILES=()
MANUAL_PROFILES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILES+=("$2")
            MANUAL_PROFILES=true
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
else
    # Resolve dependencies for manually specified profiles
    echo "Resolving dependencies..."
    RESOLVED_LIST=$(resolve_dependencies "${PROFILES[@]}") || exit 1
    mapfile -t PROFILES < <(echo "$RESOLVED_LIST" | sort_by_order)
    echo "Upgrade order: ${PROFILES[*]}"
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

for profile in "${PROFILES[@]}"; do
    PROFILE_DIR="$PROFILES_DIR/$profile"
    SETUP_SCRIPT="$PROFILE_DIR/setup.sh"

    if ! is_profile_available "$profile"; then
        echo ""
        echo "Skipping unavailable profile: $profile"
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
