#!/usr/bin/env bash

# macOS Installation Script
# - Discovers and presents available bundles
# - Resolves bundle dependencies
# - Handles preflight (sudo caching)
# - Installs Homebrew
# - Delegates bundle setup to upgrade.sh

set -e

# Prevent system sleep during installation (display, idle, disk, system)
caffeinate -dims -w $$ &

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PLATFORM_DIR="$DOTFILES_DIR/platforms/macos"
# shellcheck disable=SC2034
BUNDLES_DIR="$PLATFORM_DIR/bundles"
BUNDLES_FILE="$DOTFILES_DIR/.bundles"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

## Parse flags
SELECT_BUNDLES=()
REMOVE_BUNDLES=()
REVEALED=()
AUTO_CONFIRM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --select=*)
            SELECT_BUNDLES+=("${1#*=}")
            shift
            ;;
        --select)
            SELECT_BUNDLES+=("$2")
            shift 2
            ;;
        --remove=*)
            REMOVE_BUNDLES+=("${1#*=}")
            shift
            ;;
        --remove)
            REMOVE_BUNDLES+=("$2")
            shift 2
            ;;
        --reveal=*)
            REVEALED+=("${1#*=}")
            shift
            ;;
        --reveal)
            REVEALED+=("$2")
            shift 2
            ;;
        --yes|-y)
            AUTO_CONFIRM="yes"
            shift
            ;;
        --no|-n)
            AUTO_CONFIRM="no"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

## Determine install vs upgrade mode
if [[ -f "$BUNDLES_FILE" ]]; then
    MODE="upgrade"
else
    MODE="install"
fi

echo "Mode: $MODE"

## Bundle selection
BUNDLES=()

if [[ "$MODE" == "upgrade" ]]; then
    # Load currently installed bundles
    INSTALLED_BUNDLES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] && INSTALLED_BUNDLES+=("$line")
    done < "$BUNDLES_FILE"

    # Start with installed bundles
    BUNDLES=("${INSTALLED_BUNDLES[@]}")

    # Handle --select (additive)
    for bundle in "${SELECT_BUNDLES[@]}"; do
        # shellcheck disable=SC2076
        if [[ ! " ${BUNDLES[*]} " =~ " $bundle " ]]; then
            BUNDLES+=("$bundle")
        fi
    done

    # Handle --remove
    if [[ ${#REMOVE_BUNDLES[@]} -gt 0 ]]; then
        FILTERED_BUNDLES=()
        for bundle in "${BUNDLES[@]}"; do
            # shellcheck disable=SC2076
            if [[ ! " ${REMOVE_BUNDLES[*]} " =~ " $bundle " ]]; then
                FILTERED_BUNDLES+=("$bundle")
            fi
        done
        BUNDLES=("${FILTERED_BUNDLES[@]}")
    fi

    # If no flags provided, show interactive menu
    if [[ ${#SELECT_BUNDLES[@]} -eq 0 && ${#REMOVE_BUNDLES[@]} -eq 0 ]]; then
        echo ""
        echo "Installed bundles:"
        for bundle in "${INSTALLED_BUNDLES[@]}"; do
            echo "  ✓ $bundle"
        done

        # Show available bundles (not yet installed)
        echo ""
        echo "Available to add:"

        declare -a AVAILABLE_IDS=()
        MENU_NUM=0

        while IFS='|' read -r id name desc _order requires; do
            [[ -z "$id" ]] && continue

            # Skip if already installed
            # shellcheck disable=SC2076
            if [[ " ${INSTALLED_BUNDLES[*]} " =~ " $id " ]]; then
                continue
            fi

            MENU_NUM=$((MENU_NUM + 1))
            AVAILABLE_IDS+=("$id")

            if [[ -n "$requires" ]]; then
                echo "  $MENU_NUM) $name - $desc [requires: $requires]"
            else
                echo "  $MENU_NUM) $name - $desc"
            fi
        done < <(discover_bundles)

        if [[ ${#AVAILABLE_IDS[@]} -eq 0 ]]; then
            echo "  (all available bundles are installed)"
        fi

        echo ""
        echo "Select bundles to add (comma-separated, or Enter to skip):"
        echo -n "Selection: "
        read -r SELECTION < /dev/tty
        echo "$SELECTION"  # Echo to log

        # Add newly selected bundles
        if [[ -n "$SELECTION" ]]; then
            SELECTION="${SELECTION//,/ }"
            for choice in $SELECTION; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#AVAILABLE_IDS[@]} ]]; then
                    idx=$((choice - 1))
                    selected_id="${AVAILABLE_IDS[$idx]}"
                    BUNDLES+=("$selected_id")
                fi
            done
        fi
    fi
else
    # Install mode
    if [[ ${#SELECT_BUNDLES[@]} -gt 0 ]]; then
        # Use --select flags directly
        BUNDLES=("${SELECT_BUNDLES[@]}")
    else
        # Prompt for selection
        echo ""
        echo "Available bundles:"
        echo ""

        declare -a BUNDLE_IDS=()
        MENU_NUM=0

        while IFS='|' read -r id name desc _order requires; do
            [[ -z "$id" ]] && continue

            MENU_NUM=$((MENU_NUM + 1))
            BUNDLE_IDS+=("$id")

            if [[ -n "$requires" ]]; then
                echo "  $MENU_NUM) $name - $desc [requires: $requires]"
            else
                echo "  $MENU_NUM) $name - $desc"
            fi
        done < <(discover_bundles)

        echo ""
        echo "Select bundles (comma-separated, e.g., 1,2):"
        echo "Dependencies will be resolved automatically."
        echo ""

        echo -n "Selection: "
        read -r SELECTION < /dev/tty
        echo "$SELECTION"  # Echo to log

        if [[ -n "$SELECTION" ]]; then
            SELECTION="${SELECTION//,/ }"
            for choice in $SELECTION; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#BUNDLE_IDS[@]} ]]; then
                    idx=$((choice - 1))
                    selected_id="${BUNDLE_IDS[$idx]}"
                    # shellcheck disable=SC2076
                    [[ ! " ${BUNDLES[*]} " =~ " $selected_id " ]] && BUNDLES+=("$selected_id")
                fi
            done
        fi
    fi

    if [[ ${#BUNDLES[@]} -eq 0 ]]; then
        echo "Error: No bundles selected"
        exit 1
    fi
fi

## Prompt for preferences/dock in upgrade mode
RUN_PREFERENCES=true
RUN_DOCK=true

if [[ "$MODE" == "upgrade" ]]; then
    if [[ "$AUTO_CONFIRM" == "yes" ]]; then
        RUN_PREFERENCES=true
        RUN_DOCK=true
    elif [[ "$AUTO_CONFIRM" == "no" ]]; then
        RUN_PREFERENCES=false
        RUN_DOCK=false
    else
        echo ""
        echo "Note: Re-running these scripts will reset settings to dotfiles defaults."
        echo "      Dock configuration will replace any manually added apps/icons."
        echo ""
        echo -n "Re-run system preferences? [y/N]: "
        read -r PREFS_ANSWER < /dev/tty
        [[ "$PREFS_ANSWER" =~ ^[Yy]$ ]] && RUN_PREFERENCES=true || RUN_PREFERENCES=false

        echo -n "Re-run dock configuration? [y/N]: "
        read -r DOCK_ANSWER < /dev/tty
        [[ "$DOCK_ANSWER" =~ ^[Yy]$ ]] && RUN_DOCK=true || RUN_DOCK=false
    fi
fi

## Resolve dependencies and sort by order
echo ""
echo "Resolving dependencies..."

RESOLVED_LIST=$(resolve_dependencies "${BUNDLES[@]}") || exit 1
RESOLVED_BUNDLES=()
while IFS= read -r line; do
    [[ -n "$line" ]] && RESOLVED_BUNDLES+=("$line")
done < <(echo "$RESOLVED_LIST" | sort_by_order)

echo "Installation order: ${RESOLVED_BUNDLES[*]}"

# Create snapshot before modifying bundles (upgrade mode only)
if [[ "$MODE" == "upgrade" ]]; then
    echo ""
    create_snapshot "pre-bundle-change"
fi

# Save resolved bundles for future upgrades
printf '%s\n' "${RESOLVED_BUNDLES[@]}" > "$BUNDLES_FILE"

## Preflight: Request permissions and setup temporary sudo
if [[ -f "$PLATFORM_DIR/preflight.sh" ]]; then
    source "$PLATFORM_DIR/preflight.sh"
    trap preflight_cleanup EXIT
fi

## Install Homebrew (if not present)
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

    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Use local cache if available
if [[ -n "$DOTFILES_SOURCE_DIR" && -d "$DOTFILES_SOURCE_DIR/.cache/homebrew" ]]; then
    export HOMEBREW_CACHE="$DOTFILES_SOURCE_DIR/.cache/homebrew"
    export HOMEBREW_NO_AUTO_UPDATE=1
    echo "Using local Homebrew cache: $HOMEBREW_CACHE"
fi

## Run bundle setup via upgrade.sh (--managed: install.sh handles snapshots and preferences)
DOTFILES_MODE="$MODE" "$DOTFILES_DIR/scripts/upgrade.sh" --managed

## Offer secrets restore on first install
if [[ "$MODE" == "install" ]]; then
    # Check if there are actual encrypted keys (not just the age key itself)
    HAS_SECRET_KEYS=false
    for pattern in "$DOTFILES_DIR"/secrets/ssh/*.age "$DOTFILES_DIR"/secrets/gpg/*.age; do
        if [[ -e "$pattern" ]]; then
            HAS_SECRET_KEYS=true
            break
        fi
    done

    if [[ "$HAS_SECRET_KEYS" == true ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  Secrets restoration"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        echo "Encrypted SSH/GPG keys were found in this repo."
        echo "Restoring them now will set up SSH and GPG for this machine."

        RUN_SECRETS=false
        if [[ "$AUTO_CONFIRM" == "yes" ]]; then
            RUN_SECRETS=true
        elif [[ "$AUTO_CONFIRM" != "no" ]]; then
            echo ""
            echo -n "Restore secrets now? [y/N]: "
            read -r SECRETS_ANSWER < /dev/tty
            [[ "$SECRETS_ANSWER" =~ ^[Yy]$ ]] && RUN_SECRETS=true
        fi

        if [[ "$RUN_SECRETS" == true ]]; then
            if "$DOTFILES_DIR/scripts/secrets.sh" restore; then
                echo "  Secrets restored successfully."
            else
                echo ""
                echo "  Secrets restore did not complete."
                echo "  You can retry later with: just secrets restore"
            fi
        else
            echo ""
            echo "  Skipped. You can restore later with: just secrets restore"
        fi
    fi
fi

## Post-install system configuration
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  System configuration"
echo "════════════════════════════════════════════════════════════"

# Enable Touch ID for sudo (skip if already configured)
SUDO_LOCAL="/etc/pam.d/sudo_local"
if ! grep -q "pam_tid.so" "$SUDO_LOCAL" 2>/dev/null; then
    echo "Enabling Touch ID for sudo..."
    echo "auth       sufficient     pam_tid.so" | sudo tee "$SUDO_LOCAL" > /dev/null
    echo "  ✓ Touch ID enabled"
fi

# Change default shell to Homebrew's zsh (skip silently if already done)
HOMEBREW_ZSH="$(brew --prefix)/bin/zsh"
if [[ -x "$HOMEBREW_ZSH" ]]; then
    if ! grep -q "$HOMEBREW_ZSH" /etc/shells; then
        echo "Adding Homebrew zsh to /etc/shells..."
        echo "$HOMEBREW_ZSH" | sudo tee -a /etc/shells > /dev/null
    fi

    if [[ "$SHELL" != "$HOMEBREW_ZSH" ]]; then
        echo "Changing default shell to Homebrew zsh..."
        sudo chsh -s "$HOMEBREW_ZSH" "$USER"
    fi
fi

# Run macOS preferences
if [[ "$RUN_PREFERENCES" == "true" && -f "$PLATFORM_DIR/preferences.sh" ]]; then
    echo ""
    echo "Applying macOS preferences..."
    "$PLATFORM_DIR/preferences.sh"
fi

# Run dock configuration
if [[ "$RUN_DOCK" == "true" && -f "$PLATFORM_DIR/dock.sh" ]]; then
    echo ""
    "$PLATFORM_DIR/dock.sh"
fi

echo ""
echo "macOS installation complete!"
