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

# Encrypt unencrypted files in all secrets directories
[doc("Encrypt unencrypted files. Use --dry-run to preview.")]
sync *args:
    "{{SECRETS_SCRIPT}}" sync {{args}}

# Restore secrets from encrypted storage (cloud + local)
[doc("Restore secrets. Auto-detects cloud backup. Use --dir for custom cloud location.")]
[arg("ssh", long="ssh", value="true")]
[arg("gpg", long="gpg", value="true")]
[arg("dir", long)]
restore ssh="" gpg="" dir="":
    #!/usr/bin/env bash
    set -e

    # First, try to restore from cloud (gets age passphrase into Keychain)
    restore_cloud() {
        echo "Checking for cloud backup..."
        if "{{SECRETS_SCRIPT}}" _cloud-restore {{if dir != "" { "--dir " + dir } else { "" } }}; then
            echo ""
        else
            echo "  No cloud backup found (continuing with manual passphrase)"
            echo ""
        fi
    }

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
        for f in "{{SECRETS_DIR}}"/gpg/*.age; do
            [ -e "$f" ] || { echo "  No GPG keys found in secrets/gpg/"; return 0; }
            break
        done

        # Check if loopback already enabled in config
        local gpg_conf="$HOME/.gnupg/gpg-agent.conf"
        local loopback_added=false
        if ! grep -q "^allow-loopback-pinentry" "$gpg_conf" 2>/dev/null; then
            mkdir -p "$HOME/.gnupg"
            echo "allow-loopback-pinentry" >> "$gpg_conf"
            loopback_added=true
            gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true
        fi

        # Cleanup function to restore config
        cleanup_loopback() {
            if [[ "$loopback_added" == true ]]; then
                # Handle both regular files and symlinks
                if [[ -L "$gpg_conf" ]]; then
                    # For symlinks, we need to edit the actual file
                    local real_conf
                    real_conf=$(readlink -f "$gpg_conf")
                    sed -i '' '/^allow-loopback-pinentry$/d' "$real_conf" 2>/dev/null || true
                elif [[ -f "$gpg_conf" ]]; then
                    sed -i '' '/^allow-loopback-pinentry$/d' "$gpg_conf" 2>/dev/null || true
                fi
                gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true
            fi
        }
        trap cleanup_loopback RETURN

        for f in "{{SECRETS_DIR}}"/gpg/*.age; do
            [ -e "$f" ] || continue
            name=$(basename "$f" .age)
            # Extract keyid from filename (e.g., "KEYID.asc" -> "KEYID")
            keyid=$(echo "$name" | sed 's/\.asc$//')

            echo ""
            echo "  Restoring key $keyid..."

            # Try to get passphrase from cloud
            local KEY_PASSPHRASE
            KEY_PASSPHRASE=$("{{SECRETS_SCRIPT}}" _cloud-get-gpg-passphrase "$keyid" {{if dir != "" { "--dir " + dir } else { "" } }} 2>/dev/null) || true

            if [[ -z "$KEY_PASSPHRASE" ]]; then
                echo "  No cloud passphrase found for $keyid"
                echo "  Enter passphrase for this key:"
                echo -n "  Passphrase: "
                read -rs KEY_PASSPHRASE < /dev/tty
                echo ""
            else
                echo "  ✓ Retrieved passphrase from cloud"
            fi

            # Decrypt and import
            "{{SECRETS_SCRIPT}}" decrypt-raw "$f" /tmp/"$name"
            echo "$KEY_PASSPHRASE" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
                --import /tmp/"$name" 2>&1 || {
                echo "  ✗ Import failed (wrong passphrase?)"
                rm -P /tmp/"$name"
                continue
            }
            rm -P /tmp/"$name"
            echo "  ✓ Key $keyid imported"
        done
        echo ""
        echo "GPG keys restored."
    }

    # Always try cloud restore first (gets passphrase into Keychain)
    restore_cloud

    # If neither flag specified, do all
    if [[ -z "{{ssh}}" && -z "{{gpg}}" ]]; then
        restore_ssh
        restore_gpg
    else
        [[ "{{ssh}}" == "true" ]] && restore_ssh
        [[ "{{gpg}}" == "true" ]] && restore_gpg
    fi

# Backup secrets to encrypted storage (local + cloud)
[doc("Backup secrets. Use --dir to set up cloud backup location.")]
[arg("ssh", long="ssh", value="true")]
[arg("gpg", long="gpg", value="true")]
[arg("dir", long)]
backup ssh="" gpg="" dir="":
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
        mkdir -p "{{SECRETS_DIR}}"/gpg
        if ! gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -q "^sec"; then
            echo "  No GPG secret keys found."
            return 0
        fi

        # Get list of key IDs
        local keyids=()
        while IFS= read -r line; do
            keyid=$(echo "$line" | awk -F'/' '{print $2}' | awk '{print $1}')
            keyids+=("$keyid")
        done < <(gpg --list-secret-keys --keyid-format LONG | grep -E "^sec")

        # Check which keys need backup
        local keys_to_backup=()
        for keyid in "${keyids[@]}"; do
            if "{{SECRETS_SCRIPT}}" _is-gpg-backed-up "$keyid" {{if dir != "" { "--dir " + dir } else { "" } }} 2>/dev/null; then
                echo "  ✓ Key $keyid already backed up (skipping)"
            else
                keys_to_backup+=("$keyid")
            fi
        done

        if [[ ${#keys_to_backup[@]} -eq 0 ]]; then
            echo "  All GPG keys already backed up."
            echo "GPG backup complete."
            return 0
        fi

        # Check if loopback already enabled in config
        local gpg_conf="$HOME/.gnupg/gpg-agent.conf"
        local loopback_added=false
        if ! grep -q "^allow-loopback-pinentry" "$gpg_conf" 2>/dev/null; then
            mkdir -p "$HOME/.gnupg"
            echo "allow-loopback-pinentry" >> "$gpg_conf"
            loopback_added=true
            gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true
        fi

        # Cleanup function to restore config
        cleanup_loopback() {
            if [[ "$loopback_added" == true ]]; then
                # Handle both regular files and symlinks
                if [[ -L "$gpg_conf" ]]; then
                    # For symlinks, we need to edit the actual file
                    local real_conf
                    real_conf=$(readlink -f "$gpg_conf")
                    sed -i '' '/^allow-loopback-pinentry$/d' "$real_conf" 2>/dev/null || true
                elif [[ -f "$gpg_conf" ]]; then
                    sed -i '' '/^allow-loopback-pinentry$/d' "$gpg_conf" 2>/dev/null || true
                fi
                gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true
            fi
        }
        trap cleanup_loopback RETURN

        # Process each key that needs backup
        for keyid in "${keys_to_backup[@]}"; do
            echo ""
            echo "  Backing up key $keyid..."
            echo "  Enter passphrase for this key:"
            echo -n "  Passphrase: "
            read -rs KEY_PASSPHRASE < /dev/tty
            echo ""

            # Export the key
            echo "  Exporting key..."
            echo "$KEY_PASSPHRASE" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
                --export-secret-keys --armor "$keyid" > /tmp/gpg-"$keyid".asc

            # Check if export succeeded (non-empty file)
            if [[ ! -s /tmp/gpg-"$keyid".asc ]]; then
                echo "  ✗ Export failed (wrong passphrase?)"
                rm -f /tmp/gpg-"$keyid".asc
                continue
            fi

            # Encrypt and store the key
            "{{SECRETS_SCRIPT}}" encrypt-raw /tmp/gpg-"$keyid".asc "{{SECRETS_DIR}}"/gpg/"$keyid".asc.age
            rm -P /tmp/gpg-"$keyid".asc

            # Store passphrase in cloud
            "{{SECRETS_SCRIPT}}" _cloud-backup-gpg-passphrase "$keyid" "$KEY_PASSPHRASE" {{if dir != "" { "--dir " + dir } else { "" } }}

            echo "  ✓ Key $keyid backed up"
        done
        echo ""
        echo "GPG backup complete."
    }

    backup_cloud() {
        echo "Backing up age passphrase to cloud..."
        "{{SECRETS_SCRIPT}}" _cloud-backup {{if dir != "" { "--dir " + dir } else { "" } }} || {
            echo "  Cloud backup skipped (use --dir to configure)"
            return 1
        }
    }

    # Determine what to backup
    do_ssh=false
    do_gpg=false
    if [[ -z "{{ssh}}" && -z "{{gpg}}" ]]; then
        do_ssh=true
        do_gpg=true
    else
        [[ "{{ssh}}" == "true" ]] && do_ssh=true
        [[ "{{gpg}}" == "true" ]] && do_gpg=true
    fi

    # GPG backup requires cloud (for passphrase storage)
    # Set up cloud first if GPG is included
    cloud_ready=false
    if [[ "$do_gpg" == true ]]; then
        if backup_cloud; then
            cloud_ready=true
        else
            echo ""
            echo "GPG backup requires cloud storage for passphrase backup."
            echo "Run: just secrets backup --dir <cloud-path>"
            echo ""
            echo "Or backup SSH keys only: just secrets backup --ssh"
            exit 1
        fi
        echo ""
    fi

    # Backup SSH keys (doesn't require cloud)
    if [[ "$do_ssh" == true ]]; then
        backup_ssh
        echo ""
    fi

    # Backup GPG keys (cloud already set up above)
    if [[ "$do_gpg" == true ]]; then
        backup_gpg
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
