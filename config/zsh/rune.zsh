# ============================================================================
# Rune — Dotfiles CLI
# ============================================================================
# Unified command for managing dotfiles from any directory.
# Shell-level commands (run, load) are handled directly to avoid subshell
# limitations. Everything else passes through to just.

# Find a secrets file across the hierarchy (global → platform → bundles)
# Returns matching paths in precedence order (least → most specific)
_rune_secrets_find() {
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local search="$1"
    [[ "$search" != *.age ]] && search="${search}.age"

    local dirs=("$dotfiles_dir/secrets" "$dotfiles_dir/platforms/macos/secrets")
    if [[ -d "$dotfiles_dir/loaded" ]]; then
        local d
        for d in "$dotfiles_dir"/loaded/*/; do
            [[ -d "${d}secrets" ]] && dirs+=("${d}secrets")
        done
    fi

    local dir
    for dir in "${dirs[@]}"; do
        [[ -f "$dir/$search" ]] && echo "$dir/$search"
    done
}

rune() {
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"

    case "$1" in
        run)
            # Run a command with all secrets as env vars (ephemeral)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Usage: rune run <command> [args...]" >&2
                return 1
            fi
            local secrets
            secrets=$("$dotfiles_dir/scripts/secrets.sh" env --inline) || return 1
            env $secrets "$@"
            ;;

        load)
            # Load a secrets file into the current shell (persistent for session)
            shift
            local name="$1"
            if [[ -z "$name" ]]; then
                echo "Usage: rune load <secrets-file | path>" >&2
                return 1
            fi

            local files=""
            if [[ "$name" == */* ]]; then
                # Direct path — single file, no hierarchy merge
                local target="$name"
                [[ "$target" != *.age ]] && target="${target}.age"
                [[ -f "$target" ]] || return 0
                files="$target"
            else
                # Name only — search hierarchy and merge
                files=$(_rune_secrets_find "$name")
                if [[ -z "$files" ]]; then
                    echo "rune load: $name not found in secrets directories" >&2
                    return 1
                fi
            fi

            while IFS= read -r f; do
                local content
                content=$("$dotfiles_dir/scripts/secrets.sh" decrypt-raw "$f" "-" 2>/dev/null) || continue
                while IFS= read -r line; do
                    [[ -z "$line" || "$line" == \#* ]] && continue
                    [[ "$line" == *=* ]] || continue
                    export "$line"
                done <<< "$content"
            done <<< "$files"
            ;;

        *)
            # Everything else passes through to just
            just --justfile "$dotfiles_dir/justfile" \
                 --working-directory "$dotfiles_dir" "$@"
            ;;
    esac
}

# Backward compatibility aliases
srun() { rune run "$@"; }
sload() { rune load "$@"; }
