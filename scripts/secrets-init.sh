#!/usr/bin/env bash

# Secrets Initialization Script
# Sets up age encryption with Keychain integration for Touch ID access
#
# Supports two modes:
# 1. Bootstrap (new machine): Encrypted key exists → decrypt with password
# 2. Fresh setup: No keys exist → generate new key → encrypt with password

set -e

# Auto-detect dotfiles directory from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$SCRIPT_DIR")}"
SECRETS_DIR="$DOTFILES_DIR/secrets"
AGE_KEY_FILE="$SECRETS_DIR/keys.txt"
AGE_KEY_ENCRYPTED="$SECRETS_DIR/keys.txt.age"
SOPS_CONFIG="$DOTFILES_DIR/.sops.yaml"
KEYCHAIN_SERVICE="dotfiles-age"
KEYCHAIN_ACCOUNT="age-encryption-key"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[secrets] $1${NC}"; }
warn() { echo -e "${YELLOW}[secrets] WARNING: $1${NC}"; }
error() { echo -e "${RED}[secrets] ERROR: $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[secrets] $1${NC}"; }

# Check dependencies
check_deps() {
    command -v age &> /dev/null || error "age not found. Run: brew install age"
    command -v age-keygen &> /dev/null || error "age-keygen not found. Run: brew install age"
    command -v sops &> /dev/null || error "sops not found. Run: brew install sops"
    command -v expect &> /dev/null || error "expect not found (usually pre-installed on macOS)"
}

# Get password from user and store in Keychain
setup_keychain() {
    if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" &> /dev/null; then
        log "Age password already in Keychain (Touch ID enabled)"
        read -p "Use existing Keychain password? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            return 0
        fi
        security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" &> /dev/null || true
    fi

    log "Storing age password in Keychain for Touch ID access..."
    echo ""
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│  AGE ENCRYPTION PASSWORD                                  │"
    echo "│  From Apple Passwords: 'Dotfiles - Age Encryption Key'    │"
    echo "│  (This encrypts your age key for safe git storage)        │"
    echo "└────────────────────────────────────────────────────────────┘"
    echo ""
    read -r -s -p "Age password: " AGE_PASSWORD
    echo

    if [[ -z "$AGE_PASSWORD" ]]; then
        error "Password cannot be empty"
    fi

    # Store in Keychain
    security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$AGE_PASSWORD" -T ""
    log "Password stored in Keychain"
    echo ""
    info "NOTE: macOS will show a Keychain access dialog."
    info "Enter your macOS login password and click 'Always Allow'"
    info "to enable Touch ID for future access."
    echo ""
}

# Retrieve password from Keychain
get_password() {
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null || \
        error "Failed to retrieve password from Keychain"
}

# Bootstrap mode: Decrypt existing age key
bootstrap_mode() {
    log "Bootstrap mode: Decrypting age key from repo..."

    setup_keychain
    local password
    password=$(get_password)

    # Decrypt the age key using the password
    # age -d reads passphrase from /dev/tty, so we use expect
    log "Decrypting age key..."
    expect << EXPECT_EOF || error "Failed to decrypt age key. Wrong password?"
spawn age -d -o "$AGE_KEY_FILE" "$AGE_KEY_ENCRYPTED"
expect "Enter passphrase:"
send "$password\r"
expect eof
EXPECT_EOF

    chmod 600 "$AGE_KEY_FILE"

    # Extract and display public key
    AGE_PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | sed 's/.*: //')
    log "Age key restored successfully"
    log "Public key: $AGE_PUBLIC_KEY"
}

# Fresh setup mode: Generate new age key
fresh_setup_mode() {
    log "Fresh setup: Generating new age key..."

    setup_keychain
    local password
    password=$(get_password)

    # Create secrets directory
    mkdir -p "$SECRETS_DIR"

    # Generate age key pair
    log "Generating age key pair..."
    age-keygen > "$AGE_KEY_FILE"
    chmod 600 "$AGE_KEY_FILE"

    # Extract public key
    AGE_PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | sed 's/.*: //')

    if [[ -z "$AGE_PUBLIC_KEY" ]]; then
        error "Failed to generate age key"
    fi

    log "Public key: $AGE_PUBLIC_KEY"

    # Encrypt the age key with password for syncing
    log "Encrypting age key for safe storage in repo..."
    # age -p reads from /dev/tty, so we use expect to automate passphrase entry
    expect << EXPECT_EOF
spawn age -p -o "$AGE_KEY_ENCRYPTED" "$AGE_KEY_FILE"
expect "Enter passphrase"
send "$password\r"
expect "Confirm passphrase"
send "$password\r"
expect eof
EXPECT_EOF

    log "Encrypted key saved to: $AGE_KEY_ENCRYPTED"
    info "This file is safe to commit - it's encrypted with your password"

    # Create/update SOPS config
    log "Creating SOPS configuration..."
    cat > "$SOPS_CONFIG" << EOF
# SOPS configuration for dotfiles secrets
# Public key: $AGE_PUBLIC_KEY

creation_rules:
  - path_regex: secrets/.*\.(yaml|json|env|ini)$
    age: $AGE_PUBLIC_KEY

  - path_regex: .*\.enc\.(yaml|json|env|ini)$
    age: $AGE_PUBLIC_KEY
EOF

    # Create .gitignore for secrets
    cat > "$SECRETS_DIR/.gitignore" << 'EOF'
# Never commit unencrypted secrets
*.decrypted.*
*.dec.*

# Never commit the unencrypted private key (age identity)
keys.txt

# Encrypted identity IS safe to commit
!keys.txt.age
EOF
}

# Main logic
main() {
    check_deps
    mkdir -p "$SECRETS_DIR"

    # Determine mode
    if [[ -f "$AGE_KEY_FILE" ]]; then
        # Already have unencrypted key
        warn "Age key already exists at $AGE_KEY_FILE"

        if [[ ! -f "$AGE_KEY_ENCRYPTED" ]]; then
            warn "Encrypted key backup not found"
            read -p "Create encrypted backup now? (Y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                setup_keychain
                local password
                password=$(get_password)
                age -p -o "$AGE_KEY_ENCRYPTED" "$AGE_KEY_FILE" <<< "$password"
                log "Encrypted key saved to: $AGE_KEY_ENCRYPTED"
            fi
        fi

        read -p "Reinitialize? This will overwrite the existing key! (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            # Just ensure Keychain is set up
            setup_keychain
            log "Keychain configured. Existing key unchanged."
            exit 0
        fi
        fresh_setup_mode

    elif [[ -f "$AGE_KEY_ENCRYPTED" ]]; then
        # Bootstrap mode: have encrypted key, need to decrypt
        bootstrap_mode

    else
        # Fresh setup: no keys exist
        fresh_setup_mode
    fi

    echo ""
    echo "========================================"
    echo "Secrets initialization complete!"
    echo "========================================"
    echo ""
    echo "Age key:      $AGE_KEY_FILE (local only, gitignored)"
    echo "Encrypted:    $AGE_KEY_ENCRYPTED (safe to commit)"
    echo "Public key:   $AGE_PUBLIC_KEY"
    echo "SOPS config:  $SOPS_CONFIG"
    echo ""
    echo "Touch ID is now enabled for accessing secrets!"
    echo ""
    echo "Next steps:"
    echo "  Backup all keys:  just secrets backup"
    echo "  Backup SSH only:  just secrets backup --ssh"
    echo "  Backup GPG only:  just secrets backup --gpg"
    echo "  Check status:     just secrets status"
}

main "$@"
