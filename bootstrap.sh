#!/usr/bin/env bash

set -e  # Exit on error

TARGET_DIR="$HOME/.dotfiles"
REPO_URL="https://github.com/tsilenzio/dotfiles.git"

# Detect if running from curl pipe or locally
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    # Running from curl pipe - clone from GitHub
    echo "Downloading dotfiles from GitHub..."

    # Check if git is available
    if ! command -v git &> /dev/null; then
        echo "Error: git is required. Install Xcode Command Line Tools:"
        echo "  xcode-select --install"
        exit 1
    fi

    if [[ -d "$TARGET_DIR" ]]; then
        echo "Removing existing dotfiles at $TARGET_DIR..."
        rm -rf "$TARGET_DIR"
    fi

    git clone "$REPO_URL" "$TARGET_DIR"
else
    # Running locally - copy from source
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ "$SOURCE_DIR" != "$TARGET_DIR" ]]; then
        if [[ -d "$TARGET_DIR" ]]; then
            echo "Removing existing dotfiles at $TARGET_DIR..."
            rm -rf "$TARGET_DIR"
        fi

        echo "Copying dotfiles from $SOURCE_DIR to $TARGET_DIR..."
        mkdir -p "$TARGET_DIR"
        cp -a "$SOURCE_DIR/." "$TARGET_DIR/"
    else
        echo "Already running from $TARGET_DIR, skipping copy..."
    fi
fi

# Run install script from target location
echo ""
echo "Running install script..."
"$TARGET_DIR/install.sh"
