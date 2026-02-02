# Secrets management module
# Usage: just secrets <recipe>

set shell := ["bash", "-cu"]

SECRETS_SCRIPT := justfile_directory() / "scripts/secrets.sh"

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
sync *args:
    "{{SECRETS_SCRIPT}}" sync {{args}}

# Backup secrets to encrypted storage (--ssh, --gpg, --dir)
backup *args:
    "{{SECRETS_SCRIPT}}" backup {{args}}

# Restore secrets from encrypted storage (--ssh, --gpg, --dir)
restore *args:
    "{{SECRETS_SCRIPT}}" restore {{args}}

# Encrypt a specific file
encrypt file:
    "{{SECRETS_SCRIPT}}" encrypt-raw "{{file}}"

# Decrypt a specific file
decrypt file output="":
    "{{SECRETS_SCRIPT}}" decrypt-raw "{{file}}" "{{output}}"

# Edit an encrypted SOPS file
edit file:
    "{{SECRETS_SCRIPT}}" edit "{{file}}"

# Reset secrets (--force required to confirm)
reset *args:
    "{{SECRETS_SCRIPT}}" reset {{args}}
