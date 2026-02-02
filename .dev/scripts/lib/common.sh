#!/usr/bin/env bash
# Shared library for dev scripts

[[ -n "$_DEV_LIB_COMMON_LOADED" ]] && return 0
_DEV_LIB_COMMON_LOADED=1

# Directory resolution (assumes .dev/scripts/lib/common.sh location)
[[ -z "$DEV_DIR" ]] && DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -z "$DOTFILES_DIR" ]] && DOTFILES_DIR="$(dirname "$DEV_DIR")"
[[ -z "$CACHE_DIR" ]] && CACHE_DIR="$DOTFILES_DIR/.cache"

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    _GREEN='\033[0;32m' _YELLOW='\033[1;33m' _BLUE='\033[0;34m' _RED='\033[0;31m' _NC='\033[0m'
else
    _GREEN='' _YELLOW='' _BLUE='' _RED='' _NC=''
fi

# Logging with prefix: dev_log "tag" "message"
dev_log()   { echo -e "${_GREEN}[$1]${_NC} $2"; }
dev_warn()  { echo -e "${_YELLOW}[$1]${_NC} $2"; }
dev_info()  { echo -e "${_BLUE}[$1]${_NC} $2"; }
dev_error() { echo -e "${_RED}[$1]${_NC} $2"; }

# Create script-specific log/warn/info functions
create_logger() {
    local prefix="$1"
    log()  { dev_log "$prefix" "$1"; }
    warn() { dev_warn "$prefix" "$1"; }
    info() { dev_info "$prefix" "$1"; }
}
