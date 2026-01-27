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

cleanup_key() {
    [[ -n "$TEMP_KEY_FILE" && -f "$TEMP_KEY_FILE" ]] && rm -f "$TEMP_KEY_FILE"
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
  encrypt <file>          Encrypt a file with SOPS
  decrypt <file>          Decrypt a file with SOPS
  edit <file>             Edit an encrypted file in place
  view <file>             View decrypted contents without saving

  encrypt-raw <file>      Encrypt any file with age (for SSH/GPG keys)
  decrypt-raw <file>      Decrypt a .age file

  list                    List encrypted secrets
  status                  Check secrets setup status

  env [file]              Output decrypted env vars (default: secrets/env.age)
    --inline              Output as KEY=val KEY2=val2 (for use with env command)

Options:
  -o, --output <file>     Output file (for encrypt/decrypt)
  -h, --help              Show this help

Examples:
  $(basename "$0") init
  $(basename "$0") encrypt secrets/api-keys.yaml
  $(basename "$0") decrypt secrets/api-keys.yaml -o /tmp/keys.yaml
  $(basename "$0") edit secrets/api-keys.yaml
  $(basename "$0") encrypt-raw ~/.ssh/id_ed25519
  $(basename "$0") decrypt-raw secrets/ssh/id_ed25519.age
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

# Get password from Keychain (authenticates via Touch ID or macOS password)
get_password() {
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null || \
        error "Password not found in Keychain. Run: $0 init"
}

cmd_init() {
    exec "$DOTFILES_DIR/scripts/secrets-init.sh"
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
    find "$SECRETS_DIR" -name "*.age" -o -name "*.enc.*" 2>/dev/null | while read -r f; do
        echo "  $f"
    done
}

cmd_env() {
    local inline=false
    local env_file="$SECRETS_DIR/env.age"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --inline) inline=true; shift ;;
            *) env_file="$1"; shift ;;
        esac
    done

    [[ -f "$env_file" ]] || error "Environment file not found: $env_file (create with: secrets encrypt-raw your-env-file)"

    unlock_key

    local content
    content=$(age -d -i "$TEMP_KEY_FILE" "$env_file")

    if [[ "$inline" == true ]]; then
        echo "$content" | grep -v '^#' | grep -v '^$' | grep '=' | tr '\n' ' '
    else
        echo "$content" | grep -v '^#' | grep -v '^$' | grep '=' | while read -r line; do
            echo "export $line"
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
    local count
    count=$(find "$SECRETS_DIR" -name "*.age" 2>/dev/null | wc -l | tr -d ' ')
    echo "Encrypted files: $count"
}

# Parse arguments
[[ $# -eq 0 ]] && usage

command="$1"
shift

case "$command" in
    init)
        cmd_init
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
