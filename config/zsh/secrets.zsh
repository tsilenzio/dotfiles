# ============================================================================
# Secrets Shell Helpers
# ============================================================================
# Functions for working with age-encrypted secrets from the dotfiles system.
# Sourced by zshrc when DOTFILES_DIR is set.

# Find a secrets file across the hierarchy (global → platform → bundles)
# Returns matching paths in precedence order (least → most specific)
_secrets_find() {
    local search="$1"
    [[ "$search" != *.age ]] && search="${search}.age"

    local dirs=("$DOTFILES_DIR/secrets" "$DOTFILES_DIR/platforms/macos/secrets")
    if [[ -d "$DOTFILES_DIR/loaded" ]]; then
        local d
        for d in "$DOTFILES_DIR"/loaded/*/; do
            [[ -d "${d}secrets" ]] && dirs+=("${d}secrets")
        done
    fi

    local dir
    for dir in "${dirs[@]}"; do
        [[ -f "$dir/$search" ]] && echo "$dir/$search"
    done
}

# Run a command with all secrets as env vars (ephemeral — vars die with the process)
srun() {
    local secrets
    secrets=$("$DOTFILES_DIR/scripts/secrets.sh" env --inline) || return 1
    env $secrets "$@"
}

# Load a specific secrets file into the current shell (persistent for the session)
#   sload api-tokens.env           — search hierarchy, merge all matches (most specific wins)
#   sload path/to/api-tokens.env   — decrypt that exact file only (silent no-op if missing)
sload() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: sload <secrets-file | path>" >&2; return 1; }

    local files=""

    if [[ "$name" == */* ]]; then
        # Direct path — single file, no hierarchy merge
        local target="$name"
        [[ "$target" != *.age ]] && target="${target}.age"
        [[ -f "$target" ]] || return 0
        files="$target"
    else
        # Name only — search hierarchy and merge
        files=$(_secrets_find "$name")
        [[ -z "$files" ]] && { echo "sload: $name not found in secrets directories" >&2; return 1; }
    fi

    while IFS= read -r f; do
        local content
        content=$("$DOTFILES_DIR/scripts/secrets.sh" decrypt-raw "$f" "-" 2>/dev/null) || continue
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            [[ "$line" == *=* ]] || continue
            export "$line"
        done <<< "$content"
    done <<< "$files"
}
