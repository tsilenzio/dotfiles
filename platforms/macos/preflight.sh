#!/usr/bin/env bash

# macOS Preflight - Request permissions and setup temporary passwordless sudo
# Must be SOURCED (not executed) so functions are available to caller
#
# Usage in calling script:
#   source "$PLATFORM_DIR/preflight.sh"
#   trap preflight_cleanup EXIT

# Avoid running twice if already done this session
if [[ "$DOTFILES_PREFLIGHT_DONE" == "true" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

## Sudoers setup/cleanup (available to caller after sourcing)
PREFLIGHT_SUDOERS_FILE="/etc/sudoers.d/dotfiles-temp"

preflight_cleanup() {
    if [[ -f "$PREFLIGHT_SUDOERS_FILE" ]]; then
        sudo rm -f "$PREFLIGHT_SUDOERS_FILE"
        echo "Removed temporary sudoers entry"
    fi
}

## Request permissions
echo ""
echo "Requesting permissions (approve these prompts to continue)..."

# Trigger "administer your computer" prompt
sudo -v

# Trigger /etc/pam.d/ access dialog (for Touch ID sudo setup later)
# Touch the actual target file to grant permission for later write
SUDO_LOCAL="/etc/pam.d/sudo_local"
if [[ ! -f "$SUDO_LOCAL" ]]; then
    sudo touch "$SUDO_LOCAL"
fi

# Trigger "System Events" access prompt
echo "  Requesting System Events access..."
osascript -e 'tell application "System Events" to tell every desktop to get picture' &>/dev/null || true

echo "  ✓ Permissions requested"

## Create temporary passwordless sudo
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$PREFLIGHT_SUDOERS_FILE" > /dev/null
sudo chmod 440 "$PREFLIGHT_SUDOERS_FILE"

# Validate syntax
if ! sudo visudo -c -f "$PREFLIGHT_SUDOERS_FILE" > /dev/null 2>&1; then
    echo "Error: Invalid sudoers syntax, removing"
    sudo rm -f "$PREFLIGHT_SUDOERS_FILE"
fi

echo ""

export DOTFILES_PREFLIGHT_DONE=true
