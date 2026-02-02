#!/usr/bin/env bash

# Secrets Management Script
# Encrypt, decrypt, and edit secrets using age/SOPS with Keychain

set -e

# Dotfiles directory is always relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$DOTFILES_DIR/secrets"
AGE_KEY_ENCRYPTED="$SECRETS_DIR/keys.txt.age"
SOPS_CONFIG="$DOTFILES_DIR/.sops.yaml"
KEYCHAIN_SERVICE="dotfiles-age"
KEYCHAIN_ACCOUNT="age-encryption-key"
TEMP_KEY_FILE=""

# Detect current platform
case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    Linux) PLATFORM="linux" ;;
    *) PLATFORM="unknown" ;;
esac
PLATFORM_DIR="$DOTFILES_DIR/platforms/$PLATFORM"
LOADED_DIR="$DOTFILES_DIR/loaded"
CLOUD_SECRETS_SUBDIR=".dotfiles"

# Discover available cloud storage roots (checked in order, iCloud last)
get_cloud_roots() {
    local roots=()

    # Dropbox
    [[ -d "$HOME/Dropbox" ]] && roots+=("$HOME/Dropbox")

    # Google Drive (new location)
    for dir in "$HOME/Library/CloudStorage"/GoogleDrive-*/; do
        [[ -d "${dir}My Drive" ]] && roots+=("${dir}My Drive")
    done
    # Google Drive (legacy location)
    [[ -d "$HOME/Google Drive" ]] && roots+=("$HOME/Google Drive")

    # OneDrive (new location)
    for dir in "$HOME/Library/CloudStorage"/OneDrive-*/; do
        [[ -d "$dir" ]] && roots+=("${dir%/}")
    done
    # OneDrive (legacy location)
    [[ -d "$HOME/OneDrive" ]] && roots+=("$HOME/OneDrive")

    # iCloud (last - always exists on macOS)
    [[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]] && \
        roots+=("$HOME/Library/Mobile Documents/com~apple~CloudDocs")

    printf '%s\n' "${roots[@]}"
}

# Expand shorthand cloud provider names to full paths
# Returns the expanded path, or the original value if not a shorthand
expand_cloud_shorthand() {
    local input="$1"

    case "$input" in
        icloud)
            echo "$HOME/Library/Mobile Documents/com~apple~CloudDocs"
            ;;
        dropbox)
            echo "$HOME/Dropbox"
            ;;
        gdrive|google)
            # Find first Google Drive
            for dir in "$HOME/Library/CloudStorage"/GoogleDrive-*/; do
                if [[ -d "${dir}My Drive" ]]; then
                    echo "${dir}My Drive"
                    return 0
                fi
            done
            [[ -d "$HOME/Google Drive" ]] && echo "$HOME/Google Drive" && return 0
            echo "$input"  # Return as-is if not found
            ;;
        onedrive)
            # Find first OneDrive
            for dir in "$HOME/Library/CloudStorage"/OneDrive-*/; do
                if [[ -d "$dir" ]]; then
                    echo "${dir%/}"
                    return 0
                fi
            done
            [[ -d "$HOME/OneDrive" ]] && echo "$HOME/OneDrive" && return 0
            echo "$input"  # Return as-is if not found
            ;;
        *)
            # Not a shorthand, return as-is
            echo "$input"
            ;;
    esac
}

# Show available cloud shorthands
show_cloud_shorthands() {
    echo "Available shorthands:"
    echo "  icloud   → iCloud Drive"
    echo "  dropbox  → Dropbox"
    echo "  gdrive   → Google Drive"
    echo "  onedrive → OneDrive"
    echo ""
    echo "Or specify a custom path directly."
}

# Find existing cloud secrets directory
find_cloud_secrets_dir() {
    local roots
    roots=$(get_cloud_roots)

    while IFS= read -r root; do
        [[ -z "$root" ]] && continue
        local secrets_dir="$root/$CLOUD_SECRETS_SUBDIR"
        if [[ -d "$secrets_dir" ]]; then
            echo "$secrets_dir"
            return 0
        fi
    done <<< "$roots"

    return 1
}

cleanup_key() {
    [[ -n "$TEMP_KEY_FILE" && -f "$TEMP_KEY_FILE" ]] && rm -f "$TEMP_KEY_FILE"
    return 0
}
trap cleanup_key EXIT

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

usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  init                    Initialize secrets (create age key, setup Keychain)
  sync                    Encrypt unencrypted files in all secrets directories
    --dry-run             Show what would be encrypted without doing it

  encrypt <file>          Encrypt a file with SOPS
  decrypt <file>          Decrypt a file with SOPS
  edit <file>             Edit an encrypted file in place
  view <file>             View decrypted contents without saving

  encrypt-raw <file>      Encrypt any file with age (for SSH/GPG keys)
  decrypt-raw <file>      Decrypt a .age file

  list                    List encrypted secrets
  status                  Check secrets setup status

  env                     Output decrypted env vars from hierarchy
    --inline              Output as KEY=val KEY2=val2 (for use with env command)

Secrets directories (in load order):
  ./secrets/                              Global
  ./platforms/<os>/secrets/               Platform-specific
  ./platforms/<os>/bundles/*/secrets/     Bundle-specific (loaded only)

Options:
  -o, --output <file>     Output file (for encrypt/decrypt)
  -h, --help              Show this help

Examples:
  $(basename "$0") init
  $(basename "$0") sync --dry-run
  $(basename "$0") encrypt secrets/api-keys.yaml
  $(basename "$0") edit secrets/api-keys.yaml
  $(basename "$0") encrypt-raw ~/.ssh/id_ed25519
EOF
    exit 0
}

check_initialized() {
    if [[ ! -f "$AGE_KEY_ENCRYPTED" ]]; then
        error "Secrets not initialized. Run: $0 init"
    fi
}

unlock_key() {
    [[ -n "$TEMP_KEY_FILE" && -f "$TEMP_KEY_FILE" ]] && return 0
    check_initialized

    local password
    password=$(get_password)

    TEMP_KEY_FILE=$(mktemp)
    chmod 600 "$TEMP_KEY_FILE"

    if ! expect -c "
        log_user 0
        spawn age -d -o \"$TEMP_KEY_FILE\" \"$AGE_KEY_ENCRYPTED\"
        expect \"Enter passphrase:\"
        send \"$password\r\"
        expect eof
        catch wait result
        exit [lindex \$result 3]
    " > /dev/null 2>&1; then
        rm -f "$TEMP_KEY_FILE"
        TEMP_KEY_FILE=""
        error "Failed to decrypt key. Check your Keychain password."
    fi
}

get_age_key() {
    unlock_key
    export SOPS_AGE_KEY_FILE="$TEMP_KEY_FILE"
}

get_public_key() {
    if [[ -f "$SOPS_CONFIG" ]]; then
        grep -oE 'age1[a-z0-9]+' "$SOPS_CONFIG" | head -1
    else
        unlock_key
        grep "public key:" "$TEMP_KEY_FILE" | sed 's/.*: //'
    fi
}

# Discover all secrets directories in hierarchy order
get_secrets_dirs() {
    local dirs=()

    # Global secrets
    [[ -d "$SECRETS_DIR" ]] && dirs+=("$SECRETS_DIR")

    # Platform secrets
    [[ -d "$PLATFORM_DIR/secrets" ]] && dirs+=("$PLATFORM_DIR/secrets")

    # Bundle secrets (only loaded bundles)
    if [[ -d "$LOADED_DIR" ]]; then
        for bundle_link in "$LOADED_DIR"/*/; do
            bundle_link="${bundle_link%/}"
            [[ -L "$bundle_link" ]] || continue
            local bundle_secrets="$bundle_link/secrets"
            [[ -d "$bundle_secrets" ]] && dirs+=("$bundle_secrets")
        done
    fi

    printf '%s\n' "${dirs[@]}"
}

# Check if file should be ignored based on .secretsignore
is_ignored() {
    local file="$1"
    local dir="$2"
    local ignore_file="$dir/.secretsignore"
    local filename
    filename=$(basename "$file")

    # Always ignore these
    [[ "$filename" == ".secretsignore" ]] && return 0
    [[ "$filename" == ".gitignore" ]] && return 0
    [[ "$filename" == "README.md" ]] && return 0
    [[ "$filename" == "keys.txt" ]] && return 0

    # Check .secretsignore if it exists
    if [[ -f "$ignore_file" ]]; then
        while IFS= read -r pattern || [[ -n "$pattern" ]]; do
            # Skip comments and empty lines
            [[ "$pattern" =~ ^#.*$ ]] && continue
            [[ -z "$pattern" ]] && continue
            # Simple glob matching
            # shellcheck disable=SC2053
            [[ "$filename" == $pattern ]] && return 0
        done < "$ignore_file"
    fi

    return 1
}

# Find unencrypted files in a secrets directory
find_unencrypted() {
    local dir="$1"
    [[ -d "$dir" ]] || return

    find "$dir" -type f | while read -r file; do
        local filename
        filename=$(basename "$file")

        # Skip already encrypted files
        [[ "$filename" == *.age ]] && continue
        [[ "$filename" == *.enc.* ]] && continue

        # Skip ignored files
        is_ignored "$file" "$dir" && continue

        echo "$file"
    done
}

# Get password from Keychain (authenticates via Touch ID or macOS password)
get_password() {
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null || \
        error "Password not found in Keychain. Run: $0 init"
}

cmd_init() {
    exec "$DOTFILES_DIR/scripts/secrets-init.sh"
}

# Internal: Show cloud backup status (called from status command)
_cloud_status() {
    local dir="$1"

    # Show available cloud roots
    echo "Available cloud storage:"
    local roots found_any=false
    roots=$(get_cloud_roots)
    while IFS= read -r root; do
        [[ -z "$root" ]] && continue
        found_any=true
        local name
        case "$root" in
            *Dropbox*) name="Dropbox" ;;
            *GoogleDrive*|*"Google Drive"*) name="Google Drive" ;;
            *OneDrive*) name="OneDrive" ;;
            *"Mobile Documents"*) name="iCloud Drive" ;;
            *) name="Unknown" ;;
        esac
        local secrets_dir="$root/$CLOUD_SECRETS_SUBDIR"
        if [[ -d "$secrets_dir" ]]; then
            echo "  ✓ $name: $root"
            echo "    └── $CLOUD_SECRETS_SUBDIR/ (backup exists)"
        else
            echo "  · $name: $root"
        fi
    done <<< "$roots"

    if [[ "$found_any" == false ]]; then
        echo "  (none found)"
    fi

    echo ""

    # Show current backup location
    local secrets_dir
    if [[ -n "$dir" ]]; then
        secrets_dir="$dir"
    else
        secrets_dir=$(find_cloud_secrets_dir) || true
    fi

    if [[ -n "$secrets_dir" && -d "$secrets_dir" ]]; then
        echo "Active backup location: $secrets_dir"
        echo ""
        echo "Backed up secrets:"
        if [[ -f "$secrets_dir/age-passphrase.age" ]]; then
            echo "  ✓ age-passphrase.age"
        else
            echo "  ✗ age-passphrase.age (missing)"
        fi
        if [[ -f "$secrets_dir/gpg-passphrase.age" ]]; then
            echo "  ✓ gpg-passphrase.age"
        else
            echo "  · gpg-passphrase.age (not backed up)"
        fi
    else
        echo "No cloud backup configured."
        echo "Run: just secrets backup --dir <cloud-path>"
    fi
}

# Internal: Backup passphrases to cloud storage
_cloud_backup() {
    local dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir) dir="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Find or validate cloud directory
    local secrets_dir
    if [[ -n "$dir" ]]; then
        # Expand shorthand if applicable
        dir=$(expand_cloud_shorthand "$dir")

        # Explicit directory provided
        if [[ ! -d "$dir" ]]; then
            error "Directory does not exist: $dir

$(show_cloud_shorthands)"
        fi
        secrets_dir="$dir/$CLOUD_SECRETS_SUBDIR"
    else
        # Try to find existing backup location
        secrets_dir=$(find_cloud_secrets_dir) || true
        if [[ -z "$secrets_dir" ]]; then
            echo ""
            error "No existing cloud backup found. Use --dir to specify location.

$(show_cloud_shorthands)
Example:
  just secrets backup --dir icloud
  just secrets backup --dir dropbox
  just secrets backup --dir ~/custom/path"
        fi
    fi

    # Create secrets directory if needed
    mkdir -p "$secrets_dir"

    log "Backing up to: $secrets_dir"
    echo ""

    # Backup age passphrase (encrypted with master password)
    local age_passphrase_file="$secrets_dir/age-passphrase.age"
    log "Backing up age passphrase..."
    info "This will be encrypted with a master password you'll need to remember."
    echo ""

    # Get the current age passphrase from Keychain
    local age_passphrase
    age_passphrase=$(get_password) || error "Could not get age passphrase from Keychain"

    # Encrypt with a new master password (age will prompt)
    echo "$age_passphrase" | age -p -o "$age_passphrase_file"
    log "Age passphrase backed up: $age_passphrase_file"

    echo ""
    log "Cloud backup complete!"
    info "Remember your master password - you'll need it on new machines."
    return 0
}

# Internal: Backup a single GPG key's passphrase to cloud
_cloud_backup_gpg_passphrase() {
    local keyid="$1"
    local passphrase="$2"
    local dir="$3"

    # Expand shorthand if applicable
    [[ -n "$dir" ]] && dir=$(expand_cloud_shorthand "$dir")

    local secrets_dir
    if [[ -n "$dir" ]]; then
        secrets_dir="$dir/$CLOUD_SECRETS_SUBDIR"
    else
        secrets_dir=$(find_cloud_secrets_dir) || return 1
    fi

    mkdir -p "$secrets_dir"

    local public_key
    public_key=$(get_public_key)
    [[ -z "$public_key" ]] && error "Could not determine age public key"

    local passphrase_file="$secrets_dir/gpg-passphrase-$keyid.age"
    echo "$passphrase" | age -r "$public_key" -o "$passphrase_file"
    log "  GPG passphrase backed up: gpg-passphrase-$keyid.age"
}

# Internal: Check if GPG key is already fully backed up
_is_gpg_key_backed_up() {
    local keyid="$1"
    local dir="$2"

    # Expand shorthand if applicable
    [[ -n "$dir" ]] && dir=$(expand_cloud_shorthand "$dir")

    # Check if key file exists in secrets
    [[ -f "$SECRETS_DIR/gpg/$keyid.asc.age" ]] || return 1

    # Check if passphrase exists in cloud
    local secrets_dir
    if [[ -n "$dir" ]]; then
        secrets_dir="$dir/$CLOUD_SECRETS_SUBDIR"
    else
        secrets_dir=$(find_cloud_secrets_dir) || return 1
    fi

    [[ -f "$secrets_dir/gpg-passphrase-$keyid.age" ]] || return 1

    return 0
}

# Internal: Get GPG passphrase from cloud for a specific key
_cloud_get_gpg_passphrase() {
    local keyid="$1"
    local dir="$2"

    # Expand shorthand if applicable
    [[ -n "$dir" ]] && dir=$(expand_cloud_shorthand "$dir")

    local secrets_dir
    if [[ -n "$dir" ]]; then
        secrets_dir="$dir/$CLOUD_SECRETS_SUBDIR"
    else
        secrets_dir=$(find_cloud_secrets_dir) || return 1
    fi

    local passphrase_file="$secrets_dir/gpg-passphrase-$keyid.age"
    [[ -f "$passphrase_file" ]] || return 1

    unlock_key
    age -d -i "$TEMP_KEY_FILE" "$passphrase_file"
}

# Internal: Restore passphrases from cloud storage
_cloud_restore() {
    local dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir) dir="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Find cloud directory
    local secrets_dir
    if [[ -n "$dir" ]]; then
        # Expand shorthand if applicable
        dir=$(expand_cloud_shorthand "$dir")

        secrets_dir="$dir/$CLOUD_SECRETS_SUBDIR"
        if [[ ! -d "$secrets_dir" ]]; then
            error "No backup found at: $secrets_dir

$(show_cloud_shorthands)"
        fi
    else
        secrets_dir=$(find_cloud_secrets_dir) || \
            error "No cloud backup found. Use --dir to specify location.

$(show_cloud_shorthands)"
    fi

    log "Restoring from: $secrets_dir"
    echo ""

    # Restore age passphrase
    local age_passphrase_file="$secrets_dir/age-passphrase.age"
    if [[ -f "$age_passphrase_file" ]]; then
        log "Restoring age passphrase..."
        info "Enter your master password to decrypt:"

        local age_passphrase
        age_passphrase=$(age -d "$age_passphrase_file") || \
            error "Failed to decrypt age passphrase. Wrong master password?"

        # Store in Keychain
        security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" 2>/dev/null || true
        security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" \
            -w "$age_passphrase" -U

        log "Age passphrase restored to Keychain"
    else
        warn "No age passphrase backup found at: $age_passphrase_file"
    fi

    echo ""
    log "Cloud restore complete!"
    info "GPG passphrases will be retrieved automatically during key restore."
}

cmd_sync() {
    local dry_run=false
    [[ "$1" == "--dry-run" ]] && dry_run=true

    check_initialized

    local public_key
    public_key=$(get_public_key)
    [[ -z "$public_key" ]] && error "Could not determine public key"

    local found=false
    local dirs
    dirs=$(get_secrets_dirs)

    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue

        local files
        files=$(find_unencrypted "$dir")

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            found=true

            local output="$file.age"
            local rel_path="${file#$DOTFILES_DIR/}"

            if [[ "$dry_run" == true ]]; then
                info "Would encrypt: $rel_path → ${rel_path}.age"
            else
                log "Encrypting: $rel_path"
                age -r "$public_key" -o "$output" "$file"
                rm -f "$file"
                log "  → ${rel_path}.age"
            fi
        done <<< "$files"
    done <<< "$dirs"

    if [[ "$found" == false ]]; then
        log "All secrets are encrypted. Nothing to sync."
    elif [[ "$dry_run" == true ]]; then
        echo ""
        info "Run without --dry-run to encrypt these files"
    else
        echo ""
        log "Sync complete!"
    fi
}

cmd_encrypt() {
    local input="$1"
    local output="${2:-$input}"

    [[ -z "$input" ]] && error "No input file specified"
    [[ -f "$input" ]] || error "File not found: $input"

    get_age_key
    log "Encrypting $input..."
    sops --encrypt --in-place "$input" 2>/dev/null || sops --encrypt "$input" > "$output.enc"
    log "Encrypted: $output"
}

cmd_decrypt() {
    local input="$1"
    local output="$2"

    [[ -z "$input" ]] && error "No input file specified"
    [[ -f "$input" ]] || error "File not found: $input"

    get_age_key
    log "Decrypting $input..."
    if [[ -n "$output" ]]; then
        sops --decrypt "$input" > "$output"
        log "Decrypted to: $output"
    else
        sops --decrypt "$input"
    fi
}

cmd_edit() {
    local input="$1"

    [[ -z "$input" ]] && error "No file specified"
    [[ -f "$input" ]] || error "File not found: $input"

    get_age_key
    log "Editing $input..."
    sops "$input"
    log "Changes saved"
}

cmd_view() {
    local input="$1"

    [[ -z "$input" ]] && error "No file specified"
    [[ -f "$input" ]] || error "File not found: $input"

    get_age_key
    sops --decrypt "$input" 2>/dev/null | ${PAGER:-less}
}

cmd_encrypt_raw() {
    local input="$1"
    local output="$2"

    [[ -z "$input" ]] && error "No input file specified"
    [[ -f "$input" ]] || error "File not found: $input"

    check_initialized

    # Auto-determine output path based on input type
    if [[ -z "$output" ]]; then
        local basename
        basename=$(basename "$input")
        if [[ "$input" == *".ssh"* ]] || [[ "$basename" == id_* ]] || [[ "$basename" == *_key ]]; then
            output="$SECRETS_DIR/ssh/$basename.age"
        elif [[ "$basename" == *.asc ]] || [[ "$basename" == *.gpg ]]; then
            output="$SECRETS_DIR/gpg/$basename.age"
        else
            output="$SECRETS_DIR/$basename.age"
        fi
    fi

    local public_key
    public_key=$(get_public_key)
    [[ -z "$public_key" ]] && error "Could not determine public key"

    mkdir -p "$(dirname "$output")"
    log "Encrypting $input with age..."
    age -r "$public_key" -o "$output" "$input"
    log "Encrypted: $output"
    echo ""
    info "Original file can be safely deleted if this is the only copy you need"
}

cmd_decrypt_raw() {
    local input="$1"
    local output="${2:-${input%.age}}"

    [[ -z "$input" ]] && error "No input file specified"
    [[ -f "$input" ]] || error "File not found: $input"

    unlock_key

    log "Decrypting $input with age..."
    age -d -i "$TEMP_KEY_FILE" -o "$output" "$input"
    chmod 600 "$output"
    log "Decrypted: $output"
}

cmd_list() {
    log "Encrypted secrets:"
    echo ""

    local dirs
    dirs=$(get_secrets_dirs)

    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        [[ -d "$dir" ]] || continue

        local rel_dir="${dir#$DOTFILES_DIR/}"
        local files
        files=$(find "$dir" -type f \( -name "*.age" -o -name "*.enc.*" \) 2>/dev/null | grep -v "keys.txt.age" || true)

        if [[ -n "$files" ]]; then
            echo "  $rel_dir/"
            echo "$files" | while read -r f; do
                echo "    $(basename "$f")"
            done
            echo ""
        fi
    done <<< "$dirs"
}

cmd_env() {
    local inline=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --inline) inline=true; shift ;;
            *) shift ;;
        esac
    done

    unlock_key

    local all_content=""
    local dirs
    dirs=$(get_secrets_dirs)

    # Load env files from hierarchy: global → platform → bundles
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        [[ -d "$dir" ]] || continue

        # Find all .env.age files in this directory
        for env_file in "$dir"/*.env.age "$dir"/env.age; do
            [[ -f "$env_file" ]] || continue

            local content
            content=$(age -d -i "$TEMP_KEY_FILE" "$env_file" 2>/dev/null) || continue
            all_content+="$content"$'\n'
        done
    done <<< "$dirs"

    if [[ -z "$all_content" ]]; then
        error "No env files found. Create secrets/*.env.age files."
    fi

    # Filter and output
    local filtered
    filtered=$(echo "$all_content" | grep -v '^#' | grep -v '^$' | grep '=' || true)

    if [[ "$inline" == true ]]; then
        echo "$filtered" | tr '\n' ' '
    else
        echo "$filtered" | while read -r line; do
            [[ -n "$line" ]] && echo "export $line"
        done
    fi
}

cmd_status() {
    echo "Secrets Status"
    echo "=============="
    echo ""

    if [[ -f "$AGE_KEY_ENCRYPTED" ]]; then
        echo "Age key: OK ($AGE_KEY_ENCRYPTED)"
        local public_key
        public_key=$(get_public_key 2>/dev/null || echo "")
        if [[ -n "$public_key" ]]; then
            echo "Public key: $public_key"
        fi
    else
        echo "Age key: NOT FOUND"
    fi

    echo ""
    if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" &> /dev/null; then
        echo "Keychain: OK (password stored)"
    else
        echo "Keychain: NOT CONFIGURED"
    fi

    echo ""
    if [[ -f "$SOPS_CONFIG" ]]; then
        echo "SOPS config: OK"
    else
        echo "SOPS config: NOT FOUND"
    fi

    echo ""
    echo "Secrets directories:"
    local dirs
    dirs=$(get_secrets_dirs)
    local total_encrypted=0
    local total_unencrypted=0

    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        local rel_dir="${dir#$DOTFILES_DIR/}"
        local encrypted unencrypted

        if [[ -d "$dir" ]]; then
            encrypted=$(find "$dir" -type f -name "*.age" 2>/dev/null | grep -v "keys.txt.age" | wc -l | tr -d ' ')
            unencrypted=$(find_unencrypted "$dir" | wc -l | tr -d ' ')
            total_encrypted=$((total_encrypted + encrypted))
            total_unencrypted=$((total_unencrypted + unencrypted))
            echo "  $rel_dir/  ($encrypted encrypted, $unencrypted unencrypted)"
        else
            echo "  $rel_dir/  (not created)"
        fi
    done <<< "$dirs"

    echo ""
    echo "Total: $total_encrypted encrypted, $total_unencrypted unencrypted"

    if [[ "$total_unencrypted" -gt 0 ]]; then
        echo ""
        warn "Run 'just secrets sync' to encrypt unencrypted files"
    fi

    echo ""
    echo "Cloud Backup"
    echo "------------"
    local cloud_dir
    cloud_dir=$(find_cloud_secrets_dir 2>/dev/null) || true
    if [[ -n "$cloud_dir" ]]; then
        echo "Location: $cloud_dir"
        [[ -f "$cloud_dir/age-passphrase.age" ]] && echo "  ✓ age-passphrase" || echo "  ✗ age-passphrase"

        # Show per-key GPG passphrases
        local gpg_pass_files
        gpg_pass_files=$(find "$cloud_dir" -maxdepth 1 -name "gpg-passphrase-*.age" 2>/dev/null || true)
        if [[ -n "$gpg_pass_files" ]]; then
            echo "$gpg_pass_files" | while read -r f; do
                local keyid
                keyid=$(basename "$f" .age | sed 's/gpg-passphrase-//')
                echo "  ✓ gpg-passphrase ($keyid)"
            done
        else
            echo "  · gpg-passphrases (none backed up)"
        fi
    else
        echo "Not configured."
        echo ""
        show_cloud_shorthands
        echo "Example: just secrets backup --dir icloud"
    fi
}

# Parse arguments
[[ $# -eq 0 ]] && usage

command="$1"
shift

case "$command" in
    init)
        cmd_init
        ;;
    sync)
        cmd_sync "$1"
        ;;
    _cloud-backup)
        _cloud_backup "$@"
        ;;
    _cloud-restore)
        _cloud_restore "$@"
        ;;
    _cloud-status)
        _cloud_status "$1"
        ;;
    _cloud-backup-gpg-passphrase)
        # Usage: _cloud-backup-gpg-passphrase <keyid> <passphrase> [--dir <path>]
        keyid="$1"
        passphrase="$2"
        shift 2
        dir=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dir) dir="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        _cloud_backup_gpg_passphrase "$keyid" "$passphrase" "$dir"
        ;;
    _cloud-get-gpg-passphrase)
        # Usage: _cloud-get-gpg-passphrase <keyid> [--dir <path>]
        keyid="$1"
        shift
        dir=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dir) dir="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        _cloud_get_gpg_passphrase "$keyid" "$dir"
        ;;
    _is-gpg-backed-up)
        # Usage: _is-gpg-backed-up <keyid> [--dir <path>]
        keyid="$1"
        shift
        dir=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dir) dir="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        _is_gpg_key_backed_up "$keyid" "$dir"
        ;;
    encrypt)
        output=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o|--output) output="$2"; shift 2 ;;
                *) input="$1"; shift ;;
            esac
        done
        cmd_encrypt "$input" "$output"
        ;;
    decrypt)
        output=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o|--output) output="$2"; shift 2 ;;
                *) input="$1"; shift ;;
            esac
        done
        cmd_decrypt "$input" "$output"
        ;;
    edit)
        cmd_edit "$1"
        ;;
    view)
        cmd_view "$1"
        ;;
    encrypt-raw)
        cmd_encrypt_raw "$1" "$2"
        ;;
    decrypt-raw)
        cmd_decrypt_raw "$1" "$2"
        ;;
    list)
        cmd_list
        ;;
    status)
        cmd_status
        ;;
    env)
        cmd_env "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        error "Unknown command: $command"
        ;;
esac
