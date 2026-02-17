#!/usr/bin/env bash

# Upgrade: Re-run bundle setup scripts
# Safe to run repeatedly
#
# Usage: ./scripts/upgrade.sh [--select <name>...]
# Environment: DOTFILES_MODE - "install" or "upgrade" (default: upgrade)

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOTFILES_DIR

DOTFILES_MODE="${DOTFILES_MODE:-upgrade}"

BUNDLES_FILE="$DOTFILES_DIR/.bundles"

## Detect OS
case "$OSTYPE" in
    darwin*) OS="macos" ;;
    linux*)  OS="linux" ;;
    *)       echo "Error: Unsupported OS: $OSTYPE"; exit 1 ;;
esac

BUNDLES_DIR="$DOTFILES_DIR/platforms/$OS/bundles"

# Load shared library (provides get_bundle_conf, is_bundle_available, resolve_dependencies, sort_by_order)
source "$DOTFILES_DIR/scripts/lib/common.sh"

## Parse flags
BUNDLES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --select=*)
            BUNDLES+=("${1#*=}")
            shift
            ;;
        --select)
            BUNDLES+=("$2")
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

## Load saved bundles if none specified
if [[ ${#BUNDLES[@]} -eq 0 ]]; then
    if [[ -f "$BUNDLES_FILE" ]]; then
        BUNDLES=()
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] && BUNDLES+=("$line")
        done < "$BUNDLES_FILE"
        echo "Using saved bundles: ${BUNDLES[*]}"
    else
        echo "Error: No bundles specified and no saved bundles found."
        echo "Run './install.sh' first, or use: ./scripts/upgrade.sh --select <name>"
        exit 1
    fi
else
    # Resolve dependencies for manually specified bundles
    echo "Resolving dependencies..."
    RESOLVED_LIST=$(resolve_dependencies "${BUNDLES[@]}") || exit 1
    BUNDLES=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && BUNDLES+=("$line")
    done < <(echo "$RESOLVED_LIST" | sort_by_order)
    echo "Upgrade order: ${BUNDLES[*]}"
fi

## Ensure Homebrew is available
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

## Run each bundle's setup.sh in upgrade mode
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Running bundle upgrades"
echo "════════════════════════════════════════════════════════════"

for bundle in "${BUNDLES[@]}"; do
    BUNDLE_DIR="$BUNDLES_DIR/$bundle"
    SETUP_SCRIPT="$BUNDLE_DIR/setup.sh"

    if ! is_bundle_available "$bundle"; then
        echo ""
        echo "Skipping unavailable bundle: $bundle"
        continue
    fi

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        echo ""
        echo "Warning: No setup.sh found for bundle '$bundle', skipping..."
        continue
    fi

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "  Bundle: $bundle ($DOTFILES_MODE)"
    echo "────────────────────────────────────────────────────────────"

    # Export useful variables for the bundle script
    export DOTFILES_DIR
    export BUNDLE_DIR
    export BUNDLE_NAME="$bundle"
    export DOTFILES_MODE

    # Run the bundle's setup script
    "$SETUP_SCRIPT" "$DOTFILES_MODE"
done

## Setup loaded/ symlinks for active bundles
echo ""
echo "Setting up loaded/ symlinks..."
setup_loaded_symlinks "${BUNDLES[@]}"

echo ""
echo "════════════════════════════════════════════════════════════"
if [[ "$DOTFILES_MODE" == "install" ]]; then
    echo "  Install complete!"
else
    echo "  Upgrade complete!"
fi
echo "════════════════════════════════════════════════════════════"
