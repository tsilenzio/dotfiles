# Secrets management module
# Usage: just secrets <recipe>

set shell := ["bash", "-cu"]

SECRETS_SCRIPT := justfile_directory() / "scripts/secrets.sh"
SECRETS_DIR := justfile_directory() / "secrets"

# Show secrets commands
default:
    @just --list secrets

# Initialize age encryption + Keychain
init:
    "{{SECRETS_SCRIPT}}" init

# Check secrets setup status
status:
    "{{SECRETS_SCRIPT}}" status

# List all encrypted secrets
list:
    "{{SECRETS_SCRIPT}}" list

# Restore secrets from encrypted storage
[doc("Restore encrypted secrets. Use --ssh and/or --gpg, or neither for all.")]
[arg("ssh", long="ssh", value="true")]
[arg("gpg", long="gpg", value="true")]
restore ssh="" gpg="":
    #!/usr/bin/env bash
    set -e

    restore_ssh() {
        echo "Restoring SSH keys..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        for f in "{{SECRETS_DIR}}"/ssh/*.age; do
            [ -e "$f" ] || { echo "  No SSH keys found in secrets/ssh/"; return 0; }
            name=$(basename "$f" .age)
            echo "  Decrypting $name..."
            "{{SECRETS_SCRIPT}}" decrypt-raw "$f" ~/.ssh/"$name"
            chmod 600 ~/.ssh/"$name"
        done
        echo "SSH keys restored."
    }

    restore_gpg() {
        echo "Restoring GPG keys..."
        echo "  ┌──────────────────────────────────────────────────────────┐"
        echo "  │  GPG PASSPHRASE may be requested during import           │"
        echo "  │  (This is your GPG key passphrase, NOT the age password) │"
        echo "  └──────────────────────────────────────────────────────────┘"
        for f in "{{SECRETS_DIR}}"/gpg/*.age; do
            [ -e "$f" ] || { echo "  No GPG keys found in secrets/gpg/"; return 0; }
            name=$(basename "$f" .age)
            echo "  Decrypting and importing $name..."
            "{{SECRETS_SCRIPT}}" decrypt-raw "$f" /tmp/"$name"
            gpg --import /tmp/"$name"
            rm -P /tmp/"$name"
        done
        echo "GPG keys restored."
    }

    # If neither flag specified, do all
    if [[ -z "{{ssh}}" && -z "{{gpg}}" ]]; then
        restore_ssh
        restore_gpg
    else
        [[ "{{ssh}}" == "true" ]] && restore_ssh
        [[ "{{gpg}}" == "true" ]] && restore_gpg
    fi

# Backup secrets to encrypted storage
[doc("Backup secrets to encrypted storage. Use --ssh and/or --gpg, or neither for all.")]
[arg("ssh", long="ssh", value="true")]
[arg("gpg", long="gpg", value="true")]
backup ssh="" gpg="":
    #!/usr/bin/env bash
    set -e

    backup_ssh() {
        echo "Backing up SSH keys..."
        mkdir -p "{{SECRETS_DIR}}"/ssh
        found=0
        for key in ~/.ssh/id_*; do
            [ -e "$key" ] || continue
            [[ "$key" == *.pub ]] && continue
            echo "  Encrypting $(basename "$key")..."
            "{{SECRETS_SCRIPT}}" encrypt-raw "$key"
            found=1
        done
        [[ $found -eq 0 ]] && echo "  No SSH keys found in ~/.ssh/"
        echo "SSH backup complete."
    }

    backup_gpg() {
        echo "Backing up GPG secret keys..."
        echo "  ┌──────────────────────────────────────────────────────────┐"
        echo "  │  GPG PASSPHRASE will be requested via Touch ID/dialog    │"
        echo "  │  (This is your GPG key passphrase, NOT the age password) │"
        echo "  └──────────────────────────────────────────────────────────┘"
        mkdir -p "{{SECRETS_DIR}}"/gpg
        if ! gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -q "^sec"; then
            echo "  No GPG secret keys found."
            return 0
        fi
        gpg --list-secret-keys --keyid-format LONG | grep -E "^sec" | while read -r line; do
            keyid=$(echo "$line" | awk -F'/' '{print $2}' | awk '{print $1}')
            echo "  Exporting key $keyid..."
            gpg --export-secret-keys --armor "$keyid" > /tmp/gpg-"$keyid".asc
            "{{SECRETS_SCRIPT}}" encrypt-raw /tmp/gpg-"$keyid".asc "{{SECRETS_DIR}}"/gpg/"$keyid".asc.age
            rm -P /tmp/gpg-"$keyid".asc
        done
        echo "GPG backup complete."
    }

    # If neither flag specified, do all
    if [[ -z "{{ssh}}" && -z "{{gpg}}" ]]; then
        backup_ssh
        backup_gpg
    else
        [[ "{{ssh}}" == "true" ]] && backup_ssh
        [[ "{{gpg}}" == "true" ]] && backup_gpg
    fi

# Encrypt a specific file
encrypt file:
    "{{SECRETS_SCRIPT}}" encrypt-raw "{{file}}"

# Decrypt a specific file
decrypt file output="":
    "{{SECRETS_SCRIPT}}" decrypt-raw "{{file}}" "{{output}}"

# Edit an encrypted SOPS file
edit file:
    "{{SECRETS_SCRIPT}}" edit "{{file}}"

# Reset secrets (delete all and remove Keychain entry)
[doc("Wipe all secrets and start fresh. Requires --force to confirm.")]
[arg("force", long="force", value="true")]
reset force="":
    #!/usr/bin/env bash
    set -e

    if [[ "{{force}}" != "true" ]]; then
        echo "This will DELETE all secrets and remove the Keychain entry."
        echo "  - {{SECRETS_DIR}}/*"
        echo "  - Keychain: dotfiles-age"
        echo ""
        echo "To confirm, run: just secrets reset --force"
        exit 1
    fi

    echo "Resetting secrets..."

    # Remove all files except .gitignore
    find "{{SECRETS_DIR}}" -mindepth 1 ! -name '.gitignore' -delete 2>/dev/null || true
    echo "  ✓ Removed secrets files"

    # Remove Keychain entry
    security delete-generic-password -s "dotfiles-age" -a "age-encryption-key" 2>/dev/null && \
        echo "  ✓ Removed Keychain entry" || \
        echo "  - Keychain entry not found (already removed)"

    echo ""
    echo "Secrets reset complete. Run 'just secrets init' to start fresh."
