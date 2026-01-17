# Dotfiles task runner
# Usage: just <recipe> or just <module> <recipe>

set shell := ["bash", "-cu"]

DOTFILES_DIR := justfile_directory()

# Load modules
mod secrets ".just/secrets.just"
mod platform ".just/platform.just"

# Default recipe - show available commands
default:
    @just --list

# Run the full install script
install:
    ./install.sh

# Pull latest changes (creates rollback point first)
update:
    ./scripts/update.sh

# Apply configuration (packages + symlinks)
upgrade:
    ./scripts/upgrade.sh

# Show available rollback points
history:
    ./scripts/history.sh

# Rollback to a previous state
rollback *args:
    ./scripts/rollback.sh {{args}}

# Dev utilities for faster testing (hidden from `just --list`).
# Uses a separate justfile + [private] recipe because:
# - `[private]` only hides recipes, not module namespaces
# - Importing a module always exposes it in `just --list`
# - This approach: private recipe shells out to separate justfile
# Usage: just dev [setup|prefetch|bootstrap|install]

[private]
dev *args:
    @just --justfile {{quote(DOTFILES_DIR / ".dev/justfile")}} {{args}}
